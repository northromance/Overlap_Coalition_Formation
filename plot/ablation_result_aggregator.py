import glob
import os
import pickle
import re

import numpy as np
from scipy.io import loadmat

try:
    import mat73
except ImportError:
    mat73 = None


class AblationResultAggregator:
    RUN_CONFIG_NAME = "run_config.mat"
    PROGRESS_STATUS_NAME = "progress_status.mat"
    CACHE_FILENAME = "ablation_aggregate_cache.pkl"
    CACHE_FORMAT_VERSION = 1

    def __init__(self, search_dirs=None):
        self.search_dirs = [os.path.abspath(path) for path in (search_dirs or [])]

    def resolve_input(self, input_path=None, search_dirs=None):
        dirs = [os.path.abspath(path) for path in (search_dirs or self.search_dirs or [])]

        if input_path:
            return self._resolve_explicit_input(input_path, dirs)

        run_dir = self._find_latest_run_dir(dirs)
        if run_dir:
            return {"source_type": "run_dir", "path": run_dir}

        legacy_mat = self._find_latest_legacy_mat(dirs)
        if legacy_mat:
            return {"source_type": "legacy_mat", "path": legacy_mat}

        raise FileNotFoundError(
            "No ablation run directory or legacy ablation MAT file was found. "
            "Run Batch_Ablation.m first or pass an explicit input."
        )

    def load_results(self, input_path=None):
        resolved = self.resolve_input(input_path=input_path)
        source_type = resolved["source_type"]
        path = resolved["path"]

        if source_type == "cache_file":
            payload = self._load_cache(path)
            run_meta = {
                "source_type": "cache_file",
                "source_path": path,
                "run_dir": payload.get("run_dir"),
                "run_name": payload.get("run_name"),
                "used_cache": True,
                "cache_path": path,
                "param_snapshot": payload.get("param_snapshot"),
            }
            return payload["ablation_results"], payload["ablation_config"], run_meta

        if source_type == "legacy_mat":
            raw = self._load_legacy_aggregate(path)
            run_meta = {
                "source_type": "legacy_mat",
                "source_path": path,
                "run_dir": os.path.dirname(path),
                "run_name": os.path.splitext(os.path.basename(path))[0],
                "used_cache": False,
                "cache_path": None,
                "param_snapshot": None,
            }
            return raw["ablation_results"], raw["ablation_config"], run_meta

        run_dir = path
        run_config_data = self._load_small_mat(os.path.join(run_dir, self.RUN_CONFIG_NAME))
        progress_data = self._load_small_mat(os.path.join(run_dir, self.PROGRESS_STATUS_NAME))

        ablation_config = self._normalize_loaded_value(run_config_data.get("ablation_config", {}))
        param_snapshot = self._normalize_loaded_value(run_config_data.get("param_snapshot", {}))
        progress_status = self._normalize_loaded_value(progress_data.get("progress_status", {}))

        cache_dir = self._resolve_cache_dir(run_dir)
        cache_path = os.path.join(cache_dir, self.CACHE_FILENAME)
        progress_last_update = self._as_string(progress_status.get("last_update", ""))

        ablation_config["run_dir"] = run_dir
        ablation_config["aggregate_dir"] = cache_dir
        ablation_config["aggregate_cache_file"] = cache_path

        if os.path.isfile(cache_path):
            payload = self._load_cache(cache_path)
            if (
                payload.get("cache_format_version") == self.CACHE_FORMAT_VERSION
                and payload.get("progress_last_update", "") == progress_last_update
            ):
                run_meta = {
                    "source_type": "run_dir",
                    "source_path": run_dir,
                    "run_dir": run_dir,
                    "run_name": ablation_config.get("run_name", os.path.basename(run_dir)),
                    "used_cache": True,
                    "cache_path": cache_path,
                    "param_snapshot": param_snapshot,
                }
                return payload["ablation_results"], payload["ablation_config"], run_meta

        ablation_results = self._aggregate_from_incremental(run_dir, ablation_config, progress_status)
        payload = {
            "ablation_results": ablation_results,
            "ablation_config": ablation_config,
            "run_dir": run_dir,
            "run_name": ablation_config.get("run_name", os.path.basename(run_dir)),
            "progress_last_update": progress_last_update,
            "param_snapshot": param_snapshot,
            "cache_format_version": self.CACHE_FORMAT_VERSION,
        }
        os.makedirs(cache_dir, exist_ok=True)
        self._save_cache(cache_path, payload)

        run_meta = {
            "source_type": "run_dir",
            "source_path": run_dir,
            "run_dir": run_dir,
            "run_name": payload["run_name"],
            "used_cache": False,
            "cache_path": cache_path,
            "param_snapshot": param_snapshot,
        }
        return ablation_results, ablation_config, run_meta

    def _resolve_explicit_input(self, input_path, search_dirs):
        selector = str(input_path).strip()
        if not selector:
            return self.resolve_input(input_path=None, search_dirs=search_dirs)

        for candidate in self._explicit_candidates(selector, search_dirs):
            if os.path.isdir(candidate) or os.path.isfile(candidate):
                return self._classify_existing_path(candidate)

        matches = self._search_named_matches(selector, search_dirs)
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            match_text = "\n  - ".join(match["path"] for match in matches)
            raise FileNotFoundError(
                f"Multiple ablation inputs match '{selector}'. Please use a full path:\n  - {match_text}"
            )

        raise FileNotFoundError(f"Cannot resolve ablation input '{selector}'.")

    def _explicit_candidates(self, selector, search_dirs):
        candidates = [os.path.abspath(selector)]
        for search_dir in search_dirs:
            current = search_dir
            for _ in range(5):
                candidates.append(os.path.abspath(os.path.join(current, selector)))
                parent = os.path.dirname(current)
                if parent == current:
                    break
                current = parent

        deduped = []
        seen = set()
        for candidate in candidates:
            if candidate in seen:
                continue
            seen.add(candidate)
            deduped.append(candidate)
        return deduped

    def _classify_existing_path(self, path):
        path = os.path.abspath(path)
        if os.path.isdir(path):
            run_dir = self._find_run_dir_from_path(path)
            if run_dir:
                return {"source_type": "run_dir", "path": run_dir}
            raise FileNotFoundError(f"Path is not an ablation run directory: {path}")

        basename = os.path.basename(path)
        lower_name = basename.lower()
        if lower_name.endswith(".pkl"):
            return {"source_type": "cache_file", "path": path}
        if basename in (self.RUN_CONFIG_NAME, self.PROGRESS_STATUS_NAME):
            run_dir = self._find_run_dir_from_path(path)
            if run_dir:
                return {"source_type": "run_dir", "path": run_dir}
            raise FileNotFoundError(f"Path is not inside an ablation run directory: {path}")
        if lower_name.endswith(".mat"):
            run_dir = self._find_run_dir_from_path(path)
            if run_dir:
                return {"source_type": "run_dir", "path": run_dir}
            return {"source_type": "legacy_mat", "path": path}
        raise FileNotFoundError(f"Unsupported ablation input path: {path}")

    def _search_named_matches(self, selector, search_dirs):
        matches = []
        seen = set()
        for search_dir in search_dirs:
            if not os.path.isdir(search_dir):
                continue

            pattern = os.path.join(search_dir, "**", selector)
            for matched_path in glob.glob(pattern, recursive=True):
                if os.path.basename(os.path.normpath(matched_path)) != selector:
                    continue
                try:
                    match = self._classify_existing_path(matched_path)
                except FileNotFoundError:
                    continue
                key = (match["source_type"], os.path.abspath(match["path"]))
                if key in seen:
                    continue
                seen.add(key)
                matches.append(match)
        return sorted(matches, key=lambda item: item["path"])

    def _resolve_cache_dir(self, run_dir):
        return os.path.join(run_dir, "aggregated")

    def _aggregate_from_incremental(self, run_dir, ablation_config, progress_status):
        n_values = self._to_int_list(ablation_config.get("N_values", progress_status.get("N_values", [])))
        seeds = self._to_int_list(ablation_config.get("seeds", progress_status.get("seeds", [])))
        conditions = self._to_string_list(
            ablation_config.get("conditions", progress_status.get("conditions", []))
        )
        fixed_m = int(self._to_scalar(ablation_config.get("M", 0)))

        n_n = len(n_values)
        n_s = len(seeds)
        n_c = len(conditions)

        entry_done = self._coerce_bool_array(progress_status.get("entry_done"), (n_n, n_s, n_c))
        entry_success = self._coerce_bool_array(progress_status.get("entry_success"), (n_n, n_s, n_c))
        entry_error = self._coerce_object_array(progress_status.get("entry_error"), (n_n, n_s, n_c), "")
        result_files = self._coerce_object_array(progress_status.get("result_files"), (n_n, n_s, n_c), "")

        ablation_results = np.empty((n_n, n_s, n_c), dtype=object)
        for ni, n_value in enumerate(n_values):
            for si, seed in enumerate(seeds):
                for ci, condition_name in enumerate(conditions):
                    default_error = self._as_string(entry_error[ni, si, ci])
                    entry = {
                        "N": int(n_value),
                        "seed": int(seed),
                        "condition": condition_name,
                        "success": bool(entry_success[ni, si, ci]) if entry_done[ni, si, ci] else False,
                        "error": default_error,
                    }

                    if entry_done[ni, si, ci]:
                        result_path = self._resolve_result_path(
                            run_dir,
                            int(n_value),
                            fixed_m,
                            condition_name,
                            int(seed),
                            result_files[ni, si, ci],
                        )
                        if os.path.isfile(result_path):
                            partial_data = self._load_small_mat(result_path)
                            loaded_entry = self._normalize_loaded_value(partial_data.get("result_entry", {}))
                            if isinstance(loaded_entry, dict) and loaded_entry:
                                entry = loaded_entry
                                entry.setdefault("N", int(n_value))
                                entry.setdefault("seed", int(seed))
                                entry.setdefault("condition", condition_name)
                                if not self._as_string(entry.get("error")):
                                    entry["error"] = default_error
                                if "success" not in entry:
                                    entry["success"] = bool(entry_success[ni, si, ci])
                            else:
                                entry["success"] = False
                                entry["error"] = default_error or f"Invalid result entry: {result_path}"
                        else:
                            entry["success"] = False
                            entry["error"] = default_error or f"Missing result file: {result_path}"

                    ablation_results[ni, si, ci] = entry

        return ablation_results

    def _resolve_result_path(self, run_dir, n_value, fixed_m, condition_name, seed, relpath):
        relpath = self._as_string(relpath)
        if relpath:
            if os.path.isabs(relpath):
                return os.path.normpath(relpath)
            return os.path.normpath(os.path.join(run_dir, relpath))

        cond_key = self._sanitize_name(condition_name)
        cond_dir = os.path.join(run_dir, "by_condition", cond_key, f"N{n_value}")
        if fixed_m > 0:
            candidate = os.path.join(
                cond_dir,
                f"N{n_value}_M{fixed_m}_cond_{cond_key}_seed{seed}.mat",
            )
            if os.path.isfile(candidate):
                return candidate

        matches = sorted(glob.glob(os.path.join(cond_dir, f"*seed{seed}.mat")))
        if matches:
            return matches[0]

        return os.path.join(cond_dir, f"seed{seed}.mat")

    def _find_latest_run_dir(self, search_dirs):
        candidates = []
        for search_dir in search_dirs:
            if not os.path.isdir(search_dir):
                continue
            pattern = os.path.join(search_dir, "**", self.RUN_CONFIG_NAME)
            for run_config_file in glob.glob(pattern, recursive=True):
                run_dir = os.path.dirname(run_config_file)
                if not self._looks_like_run_dir(run_dir):
                    continue
                candidates.append(run_dir)

        if not candidates:
            return None
        candidates = sorted(set(candidates))
        return max(candidates, key=os.path.getmtime)

    def _find_latest_legacy_mat(self, search_dirs):
        candidates = []
        for search_dir in search_dirs:
            if not os.path.isdir(search_dir):
                continue
            pattern = os.path.join(search_dir, "**", "*.mat")
            for mat_path in glob.glob(pattern, recursive=True):
                if not self._is_ablation_path(mat_path):
                    continue
                if self._find_run_dir_from_path(mat_path):
                    continue
                candidates.append(os.path.abspath(mat_path))

        if not candidates:
            return None
        candidates = sorted(set(candidates))
        return max(candidates, key=os.path.getmtime)

    def _find_run_dir_from_path(self, path):
        current = os.path.abspath(path)
        if os.path.isfile(current):
            current = os.path.dirname(current)

        while True:
            if self._looks_like_run_dir(current):
                return current
            parent = os.path.dirname(current)
            if parent == current:
                break
            current = parent
        return None

    def _looks_like_run_dir(self, path):
        return (
            os.path.isfile(os.path.join(path, self.RUN_CONFIG_NAME))
            and os.path.isfile(os.path.join(path, self.PROGRESS_STATUS_NAME))
            and os.path.isdir(os.path.join(path, "by_condition"))
        )

    def _is_ablation_path(self, path):
        normalized = os.path.normcase(os.path.abspath(path))
        parts = normalized.split(os.sep)
        return "ablation" in parts

    def _load_small_mat(self, path):
        try:
            data = loadmat(path, simplify_cells=True)
            return {key: value for key, value in data.items() if not key.startswith("__")}
        except (NotImplementedError, ValueError):
            if mat73 is None:
                raise RuntimeError(
                    f"File {path} is MATLAB v7.3, but mat73 is not installed in this environment. "
                    "Install mat73 to read legacy ablation MAT files, or use a new ablation run_dir."
                )
            data = mat73.loadmat(path)
            return {key: value for key, value in data.items() if not key.startswith("__")}

    def _load_legacy_aggregate(self, path):
        raw = self._load_small_mat(path)
        if "ablation_results" not in raw:
            raise RuntimeError(f"Legacy ablation MAT does not contain ablation_results: {path}")
        return {
            "ablation_results": self._normalize_loaded_value(raw["ablation_results"]),
            "ablation_config": self._normalize_loaded_value(raw.get("ablation_config", {})),
        }

    def _load_cache(self, path):
        with open(path, "rb") as fp:
            return pickle.load(fp)

    def _save_cache(self, path, payload):
        with open(path, "wb") as fp:
            pickle.dump(payload, fp, protocol=pickle.HIGHEST_PROTOCOL)

    def _normalize_loaded_value(self, value):
        if isinstance(value, dict):
            return {key: self._normalize_loaded_value(val) for key, val in value.items()}
        if isinstance(value, list):
            return [self._normalize_loaded_value(val) for val in value]
        if isinstance(value, tuple):
            return tuple(self._normalize_loaded_value(val) for val in value)
        if isinstance(value, np.ndarray):
            if value.dtype.names:
                if value.size == 1:
                    return self._normalize_loaded_value(value.reshape(-1, order="F")[0])
                flat = np.empty(value.size, dtype=object)
                for idx, item in enumerate(value.reshape(-1, order="F")):
                    flat[idx] = self._normalize_loaded_value(item)
                return flat.reshape(value.shape, order="F")
            if value.dtype == object:
                if value.ndim == 0:
                    return self._normalize_loaded_value(value.item())
                flat = np.empty(value.size, dtype=object)
                for idx, item in enumerate(value.reshape(-1, order="F")):
                    flat[idx] = self._normalize_loaded_value(item)
                return flat.reshape(value.shape, order="F")
            if value.ndim == 0:
                return self._normalize_loaded_value(value.item())
            return value
        if isinstance(value, np.generic):
            return value.item()
        return value

    def _coerce_object_array(self, value, shape, fill_value=""):
        arr = np.empty(shape, dtype=object)
        arr[:] = fill_value
        if value is None:
            return arr

        loaded = np.asarray(value, dtype=object)
        if loaded.shape == shape:
            return loaded
        if loaded.size == 1:
            arr[:] = loaded.item()
            return arr
        if loaded.size == arr.size:
            try:
                return loaded.reshape(shape, order="F")
            except Exception:
                pass

        flat_loaded = loaded.reshape(-1, order="F")
        flat_arr = arr.reshape(-1, order="F")
        flat_arr[: min(flat_loaded.size, flat_arr.size)] = flat_loaded[: min(flat_loaded.size, flat_arr.size)]
        return arr

    def _coerce_bool_array(self, value, shape):
        obj_arr = self._coerce_object_array(value, shape, False)
        out = np.zeros(shape, dtype=bool)
        it = np.nditer(obj_arr, flags=["multi_index", "refs_ok"])
        for item in it:
            out[it.multi_index] = self._to_bool(item.item())
        return out

    def _to_bool(self, value):
        if isinstance(value, np.ndarray):
            if value.size == 0:
                return False
            return self._to_bool(value.item())
        if isinstance(value, (list, tuple)):
            if not value:
                return False
            return self._to_bool(value[0])
        if value is None:
            return False
        return bool(value)

    def _to_scalar(self, value):
        if value is None:
            return np.nan
        arr = np.asarray(value, dtype=float).ravel()
        return float(arr[0]) if arr.size else np.nan

    def _to_int_list(self, value):
        if value is None:
            return []
        arr = np.asarray(value).ravel()
        return [int(v) for v in arr.tolist()]

    def _to_string_list(self, value):
        if value is None:
            return []
        if isinstance(value, str):
            return [value]
        if isinstance(value, np.ndarray):
            return [self._as_string(v) for v in value.ravel().tolist()]
        return [self._as_string(v) for v in list(value)]

    def _as_string(self, value):
        if value is None:
            return ""
        if isinstance(value, np.ndarray):
            if value.size == 0:
                return ""
            if value.size == 1:
                return self._as_string(value.item())
            return "".join(self._as_string(item) for item in value.ravel().tolist())
        if isinstance(value, bytes):
            return value.decode("utf-8", errors="ignore")
        text = str(value)
        return "" if text == "None" else text

    def _sanitize_name(self, value):
        text = self._as_string(value).strip()
        text = re.sub(r"[^A-Za-z0-9_-]+", "_", text).strip("_")
        return text or "condition"
