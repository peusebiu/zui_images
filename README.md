# Push annotated docker images to OCI registry

Pulls dockerhub images, add annotations with stacker, push new image to OCI registry

Annotations contents are fetched from https://github.com/docker-library/docs.git, so the images should be present in this repo

## Usage
```
usage: zui_push.py [-h] [-i IMAGE] [-t TAG] [-r REGISTRY] [-n TAGS_NUM] [-u USERNAME] [-p PASSWORD]

optional arguments:
  -h, --help            show this help message and exit
  -i IMAGE, --image IMAGE
                        Image to push
  -t TAG, --tag TAG     Tag to push, if not given it will fetch last -n tags
  -r REGISTRY, --registry REGISTRY
                        Registry address
  -n TAGS_NUM, --tags-num TAGS_NUM
                        Max number of tags to push
  -u USERNAME, --username USERNAME
                        registry username
  -p PASSWORD, --password PASSWORD
                        registry password
```

## Examples

### Push last 10 tags of alpine and busybox to localhost:8080 OCI registry

```
./zui_push.py -i busybox -i alpine -r localhost:8080 -n 10
```

### Push latest, 1.19.1 and 1.19.2 golang tags to localhost:8080 OCI registry

```
./zui_push.py -i golang -t latest -t 1.19.1 -t 1.19.2 -r localhost:8080
```
