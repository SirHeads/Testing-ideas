import json
import shutil
from collections import OrderedDict

def get_all_features(container, all_configs):
    features = set(container.get('features', []))
    if 'clone_from_ctid' in container:
        parent_id = str(container['clone_from_ctid'])
        if parent_id in all_configs:
            parent_container = all_configs[parent_id]
            features.update(get_all_features(parent_container, all_configs))
    return features

def main():
    config_path = '/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json'
    backup_path = config_path + '.bak'

    # Create a backup of the original file
    shutil.copy(config_path, backup_path)

    with open(config_path, 'r') as f:
        configs = json.load(f, object_pairs_hook=OrderedDict)

    all_containers = configs['lxc_configs']

    for ctid, container in all_containers.items():
        all_features = get_all_features(container, all_containers)
        container['features'] = sorted(list(all_features))

    with open(config_path, 'w') as f:
        json.dump(configs, f, indent=2)

if __name__ == '__main__':
    main()