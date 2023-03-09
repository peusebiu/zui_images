#!/usr/bin/env python3
import argparse
import json
import requests
import subprocess
import sys
import yaml
import os

def fetch_tags(image_name):
    r = requests.get('https://registry.hub.docker.com/v2/repositories/library/{}/tags?page_size=100'.format(image_name))
    return r.json()

def add_doc_annotation(image_name):
    stackerfile_path = "stacker.yaml"
    with open(stackerfile_path) as f:
        stackerfile = yaml.safe_load(f)

    with open(os.path.join("docs", image_name, "content.md")) as f:
        doc = f.readlines()

    for line in doc:
        line 

    stackerfile['${{IMAGE_NAME}}']["annotations"]["org.opencontainers.image.description"] = "\n" + "".join(doc)

    print(stackerfile)
    with open(stackerfile_path, "w") as f:
        yaml.dump(stackerfile, f, default_style=None)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument('-i', '--image', action="append", help='Image to push')
    p.add_argument('-t', '--tag', default=[], action="append", help='Tag to push, if not given it will fetch last -n tags')
    p.add_argument('-r', '--registry', default='localhost:8080', help='Registry address')
    p.add_argument('-n', '--tags-num', default=10, type=int, help='Max number of tags to push')
    p.add_argument('-u', '--username', default="", help='registry username')
    p.add_argument('-p', '--password', default="", help='registry password')
    p.add_argument('-m', '--multiarch', default="", help='upload multiarch images')
    p.add_argument('-c', '--cosign-password', default="", help='cosign key password')

    args = p.parse_args()

    registry = args.registry
    images = args.image
    validTags = args.tag
    tags_num = args.tags_num
    username = args.username
    password = args.password
    cosign_password = args.cosign_password
    multiarch = args.multiarch
    metadata = {}

    for image in images:
        validTags = args.tag
        if len(validTags) == 0:
            tags = fetch_tags(image)
            for tag in tags["results"]:
                for image_info in tag["images"]:
                    if image_info["os"] == "linux":
                        if tag["name"] not in validTags and len(validTags) <= tags_num:
                            validTags.append(tag["name"])
        for tag in validTags:
            print("adding annotations and pushing image: {}:{}".format(image, tag))
            #add_doc_annotation(image)
            metafile='{}_{}_metadata.json'.format(image, tag)
            cmd = ["./build_push_image_regctl.sh", registry, image, tag, cosign_password, metafile, multiarch, username, password]
            print(" ".join(cmd))
            result = subprocess.run(cmd, stderr=sys.stderr, stdout=sys.stdout)
            if result.returncode != 0:
                print("pushing image: {}:{} exited with code: ".format(image, tag) + str(result.returncode))
            with open(metafile) as f:
                image_metadata = json.load(f)
            metadata.setdefault(image, {})
            metadata[image][tag] = image_metadata[image][tag]

    with open("image_metadata.json", "w") as f:
        json.dump(metadata, f)
