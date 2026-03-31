import glob
import os
import pickle

import numpy as np
from scipy.io import loadmat

try:
    import mat73
except ImportError:
    mat73 = None


class VaryMResultAggregator:
    RUN_CONFIG_NAME = 'run_config.mat'
    PROGRESS_STATUS_NAME = 'progress_status.mat'
    CACHE_FILENAME = 'varym_aggregate_cache.pkl'

    def __init__(self, search_dirs=None):
        self.search_dirs = [os.path.abspath(p) for p in (search_dirs or [])]

    def resolve_input(self, input_path=None, search_dirs=None):
        dirs = [os.path.abspath(p) for p in (search_dirs or self.search_dirs or [])]

        if input_path:
            path = os.path.abspath(input_path)
            if os.path.isdir(path):
                run_dir = self._find_run_dir_from_path(path)
                if run_dir:
                    return {'source_type': 'run_dir', 'path': run_dir}
                raise FileNotFoundError(f'未识别为 VaryM 运行目录: {path}')

            if not os.path.isfile(path):
                raise FileNotFoundError(f'输入路径不存在: {path}')

            basename = os.path.basename(path)
            lower_name = basename.lower()
            if lower_name.endswith('.pkl'):
                return {'source_type': 'cache_file', 'path': path}
            if basename in (self.RUN_CONFIG_NAME, self.PROGRESS_STATUS_NAME):
                return {'source_type': 'run_dir', 'path': os.path.dirname(path)}
            if lower_name.endswith('.mat'):
                run_dir = self._find_run_dir_from_path(path)
                if run_dir:
                    return {'source_type': 'run_dir', 'path': run_dir}
                if basename.startswith('scale_M_results'):
                    return {'source_type': 'legacy_mat', 'path': path}
                raise FileNotFoundError(f'未识别的 VaryM 输入文件: {path}')

            raise FileNotFoundError(f'不支持的输入路径: {path}')

        run_dir = self._find_latest_run_dir(dirs)
        if run_dir:
            return {'source_type': 'run_dir', 'path': run_dir}

        legacy_mat = self._find_latest_legacy_mat(dirs)
        if legacy_mat:
            return {'source_type': 'legacy_mat', 'path': legacy_mat}

        raise FileNotFoundError('未找到可用的 VaryM 运行目录或历史聚合 MAT 文件。')

    def load_results(self, input_path=None):
        resolved = self.resolve_input(input_path=input_path)
        source_type = resolved['source_type']
        path = resolved['path']

        if source_type == 'cache_file':
            payload = self._load_cache(path)
            run_meta = {
                'source_type': 'cache_file',
                'source_path': path,
                'run_dir': payload.get('run_dir'),
                'run_name': payload.get('run_name'),
                'used_cache': True,
                'cache_path': path,
                'param_snapshot': payload.get('param_snapshot'),
            }
            return payload['scale_M_results'], payload['scale_config'], run_meta

        if source_type == 'legacy_mat':
            raw = self._load_legacy_aggregate(path)
            run_meta = {
                'source_type': 'legacy_mat',
                'source_path': path,
                'run_dir': os.path.dirname(path),
                'run_name': os.path.splitext(os.path.basename(path))[0],
                'used_cache': False,
                'cache_path': None,
                'param_snapshot': None,
            }
            return raw['scale_M_results'], raw['scale_config'], run_meta

        run_dir = path
        run_config_data = self._load_small_mat(os.path.join(run_dir, self.RUN_CONFIG_NAME))
        progress_data = self._load_small_mat(os.path.join(run_dir, self.PROGRESS_STATUS_NAME))

        scale_config = self._normalize_loaded_value(run_config_data.get('scale_config', {}))
        param_snapshot = self._normalize_loaded_value(run_config_data.get('param_snapshot', {}))
        progress_status = self._normalize_loaded_value(progress_data.get('progress_status', {}))

        cache_dir = self._resolve_cache_dir(run_dir, scale_config)
        cache_path = os.path.join(cache_dir, self.CACHE_FILENAME)
        progress_last_update = self._as_string(progress_status.get('last_update', ''))

        scale_config['run_dir'] = run_dir
        scale_config['aggregate_dir'] = cache_dir
        scale_config['aggregate_cache_file'] = cache_path

        if os.path.isfile(cache_path):
            payload = self._load_cache(cache_path)
            if payload.get('progress_last_update', '') == progress_last_update:
                run_meta = {
                    'source_type': 'run_dir',
                    'source_path': run_dir,
                    'run_dir': run_dir,
                    'run_name': scale_config.get('run_name', os.path.basename(run_dir)),
                    'used_cache': True,
                    'cache_path': cache_path,
                    'param_snapshot': param_snapshot,
                }
                return payload['scale_M_results'], payload['scale_config'], run_meta

        scale_M_results = self._aggregate_from_incremental(run_dir, scale_config, progress_status)
        payload = {
            'scale_M_results': scale_M_results,
            'scale_config': scale_config,
            'run_dir': run_dir,
            'run_name': scale_config.get('run_name', os.path.basename(run_dir)),
            'progress_last_update': progress_last_update,
            'param_snapshot': param_snapshot,
        }
        os.makedirs(cache_dir, exist_ok=True)
        self._save_cache(cache_path, payload)

        run_meta = {
            'source_type': 'run_dir',
            'source_path': run_dir,
            'run_dir': run_dir,
            'run_name': payload['run_name'],
            'used_cache': False,
            'cache_path': cache_path,
            'param_snapshot': param_snapshot,
        }
        return scale_M_results, scale_config, run_meta

    def _resolve_cache_dir(self, run_dir, scale_config):
        """
        Keep cache co-located with the selected run_dir.

        Old run_config snapshots may contain absolute paths from another machine
        (for example D:\\... after the run directory has been copied to E:\\...).
        For portability we always use <run_dir>/aggregated at plotting time.
        """
        return os.path.join(run_dir, 'aggregated')

    def _aggregate_from_incremental(self, run_dir, scale_config, progress_status):
        m_values = self._to_int_list(scale_config.get('M_values', []))
        seeds = self._to_int_list(scale_config.get('seeds', []))
        alg_names = self._to_string_list(scale_config.get('alg_names', []))
        num_rounds = int(self._to_scalar(scale_config.get('num_rounds', 0)))

        n_m = len(m_values)
        n_s = len(seeds)
        n_a = len(alg_names)

        scenario_success = self._coerce_bool_array(progress_status.get('scenario_success'), (n_m, n_s))
        scenario_error = self._coerce_object_array(progress_status.get('scenario_error'), (n_m, n_s), '')
        alg_done = self._coerce_bool_array(progress_status.get('alg_done'), (n_m, n_s, n_a))
        alg_error = self._coerce_object_array(progress_status.get('alg_error'), (n_m, n_s, n_a), '')
        result_files = self._coerce_object_array(progress_status.get('result_files'), (n_m, n_s, n_a), '')

        scale_M_results = []
        for mi, m_value in enumerate(m_values):
            row = []
            for si, seed in enumerate(seeds):
                entry = {
                    'M': int(m_value),
                    'seed': int(seed),
                    'success': bool(scenario_success[mi, si]),
                    'error': self._as_string(scenario_error[mi, si]),
                    'algs': {},
                }

                for ai, alg_name in enumerate(alg_names):
                    default_error = self._as_string(alg_error[mi, si, ai])
                    alg_entry = self._make_empty_alg_entry(num_rounds, default_error)

                    if alg_done[mi, si, ai]:
                        result_path = self._resolve_result_path(
                            run_dir, alg_name, int(m_value), int(seed), result_files[mi, si, ai]
                        )
                        if os.path.isfile(result_path):
                            partial_data = self._load_small_mat(result_path)
                            loaded_entry = self._normalize_loaded_value(partial_data.get('result_entry', {}))
                            alg_entry = self._merge_alg_entry(alg_entry, loaded_entry)
                            if not alg_entry.get('error'):
                                alg_entry['error'] = default_error
                        else:
                            alg_entry['success'] = False
                            alg_entry['error'] = default_error or f'缺少结果文件: {result_path}'

                    entry['algs'][alg_name] = alg_entry

                row.append(entry)
            scale_M_results.append(row)

        return scale_M_results

    def _resolve_result_path(self, run_dir, alg_name, m_value, seed, relpath):
        relpath = self._as_string(relpath)
        if relpath:
            if os.path.isabs(relpath):
                return os.path.normpath(relpath)
            return os.path.normpath(os.path.join(run_dir, relpath))

        new_name = f'N{self._infer_fixed_n(run_dir)}_M{m_value:03d}_seed{seed}.mat'
        new_path = os.path.join(run_dir, 'by_alg', alg_name, f'M{m_value:03d}', new_name)
        if os.path.isfile(new_path):
            return new_path

        return os.path.join(run_dir, 'by_alg', alg_name, f'M{m_value:03d}', f'seed{seed}.mat')

    def _infer_fixed_n(self, run_dir):
        run_config_path = os.path.join(run_dir, self.RUN_CONFIG_NAME)
        if os.path.isfile(run_config_path):
            data = self._load_small_mat(run_config_path)
            scale_config = self._normalize_loaded_value(data.get('scale_config', {}))
            if isinstance(scale_config, dict) and 'N' in scale_config:
                try:
                    return int(self._to_scalar(scale_config.get('N')))
                except (TypeError, ValueError):
                    pass
        return 0

    def _make_empty_alg_entry(self, num_rounds, error_text):
        return {
            'computation_time': np.nan,
            'convergence_utility': np.full(num_rounds, np.nan),
            'convergence_cost': np.full(num_rounds, np.nan),
            'convergence_completed_value': np.full(num_rounds, np.nan),
            'convergence_completion': np.full(num_rounds, np.nan),
            'final_utility': np.nan,
            'final_cost': np.nan,
            'final_completed_value': np.nan,
            'final_completion': np.nan,
            'success': False,
            'error': error_text or '',
        }

    def _merge_alg_entry(self, base_entry, loaded_entry):
        if not isinstance(loaded_entry, dict):
            return base_entry

        merged = dict(base_entry)
        scalar_keys = (
            'computation_time',
            'final_utility',
            'final_cost',
            'final_completed_value',
            'final_completion',
        )
        curve_keys = (
            'convergence_utility',
            'convergence_cost',
            'convergence_completed_value',
            'convergence_completion',
        )

        for key in scalar_keys:
            if key in loaded_entry:
                merged[key] = self._to_scalar(loaded_entry[key])

        for key in curve_keys:
            if key in loaded_entry:
                merged[key] = np.asarray(loaded_entry[key], dtype=float).ravel()

        if 'success' in loaded_entry:
            merged['success'] = self._to_bool(loaded_entry['success'])
        if 'error' in loaded_entry:
            merged['error'] = self._as_string(loaded_entry['error'])
        return merged

    def _find_latest_run_dir(self, search_dirs):
        candidates = []
        for search_dir in search_dirs:
            if not os.path.isdir(search_dir):
                continue
            pattern = os.path.join(search_dir, '**', self.RUN_CONFIG_NAME)
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
            pattern = os.path.join(search_dir, '**', 'scale_M_results*.mat')
            for mat_path in glob.glob(pattern, recursive=True):
                if self._is_varym_path(mat_path):
                    candidates.append(mat_path)

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
            self._is_varym_path(path)
            and os.path.isfile(os.path.join(path, self.RUN_CONFIG_NAME))
            and os.path.isfile(os.path.join(path, self.PROGRESS_STATUS_NAME))
            and os.path.isdir(os.path.join(path, 'by_alg'))
        )

    def _is_varym_path(self, path):
        normalized = os.path.normcase(os.path.abspath(path))
        parts = normalized.split(os.sep)
        return 'varym' in parts

    def _load_small_mat(self, path):
        try:
            data = loadmat(path, simplify_cells=True)
            return {k: v for k, v in data.items() if not k.startswith('__')}
        except NotImplementedError:
            if mat73 is None:
                raise RuntimeError(
                    f'文件 {path} 是 MATLAB v7.3 格式，当前环境缺少 mat73，无法读取。'
                )
            data = mat73.loadmat(path)
            return {k: v for k, v in data.items() if not k.startswith('__')}

    def _load_legacy_aggregate(self, path):
        if mat73 is None:
            raise RuntimeError('读取历史 v7.3 聚合 MAT 文件需要 mat73，请先安装 mat73。')
        raw = mat73.loadmat(path)
        return {
            'scale_M_results': raw['scale_M_results'],
            'scale_config': raw['scale_config'],
        }

    def _load_cache(self, path):
        with open(path, 'rb') as fp:
            return pickle.load(fp)

    def _save_cache(self, path, payload):
        with open(path, 'wb') as fp:
            pickle.dump(payload, fp, protocol=pickle.HIGHEST_PROTOCOL)

    def _normalize_loaded_value(self, value):
        if isinstance(value, dict):
            return {k: self._normalize_loaded_value(v) for k, v in value.items()}
        if isinstance(value, list):
            return [self._normalize_loaded_value(v) for v in value]
        if isinstance(value, tuple):
            return tuple(self._normalize_loaded_value(v) for v in value)
        if isinstance(value, np.ndarray):
            if value.dtype.names:
                if value.size == 1:
                    return self._normalize_loaded_value(value.reshape(-1, order='F')[0])
                flat = np.empty(value.size, dtype=object)
                for idx, item in enumerate(value.reshape(-1, order='F')):
                    flat[idx] = self._normalize_loaded_value(item)
                return flat.reshape(value.shape, order='F')
            if value.dtype == object:
                if value.ndim == 0:
                    return self._normalize_loaded_value(value.item())
                flat = np.empty(value.size, dtype=object)
                for idx, item in enumerate(value.reshape(-1, order='F')):
                    flat[idx] = self._normalize_loaded_value(item)
                return flat.reshape(value.shape, order='F')
            if value.ndim == 0:
                return self._normalize_loaded_value(value.item())
            return value
        if isinstance(value, np.generic):
            return value.item()
        return value

    def _coerce_object_array(self, value, shape, fill_value=''):
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

        flat_loaded = loaded.reshape(-1, order='F')
        flat_arr = arr.reshape(-1, order='F')
        flat_arr[:min(flat_loaded.size, flat_arr.size)] = flat_loaded[:min(flat_loaded.size, flat_arr.size)]
        return arr

    def _coerce_bool_array(self, value, shape):
        obj_arr = self._coerce_object_array(value, shape, False)
        out = np.zeros(shape, dtype=bool)
        it = np.nditer(obj_arr, flags=['multi_index', 'refs_ok'])
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
            return ''
        if isinstance(value, np.ndarray):
            if value.size == 0:
                return ''
            return self._as_string(value.item())
        if isinstance(value, bytes):
            return value.decode('utf-8', errors='ignore')
        text = str(value)
        return '' if text == 'None' else text
