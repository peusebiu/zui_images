#!/usr/bin/env python3
import argparse
import json
import requests
import subprocess
import sys

def fetch_tags(image_name):
    r = requests.get('https://registry.hub.docker.com/v2/repositories/library/{}/tags?page_size=100'.format(image_name))
    return r.json()


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument('-i', '--image', action="append", help='Image to push')
    p.add_argument('-t', '--tag', default=[], action="append", help='Tag to push, if not given it will fetch last -n tags')
    p.add_argument('-r', '--registry', default='localhost:8080', help='Registry address')
    p.add_argument('-n', '--tags-num', default=10, type=int, help='Max number of tags to push')
    p.add_argument('-u', '--username', default="", help='registry username')
    p.add_argument('-p', '--password', default="", help='registry password')

    args = p.parse_args()

    registry = args.registry
    images = args.image
    validTags = args.tag
    tags_num = args.tags_num
    username = args.username
    password = args.password

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
            cmd = ["./build_push_image.sh", registry, image, tag, username, password]
            print(" ".join(cmd))
            result = subprocess.run(cmd, stderr=sys.stderr, stdout=sys.stdout)
            if result.returncode != 0:
                exit(result.returncode)
