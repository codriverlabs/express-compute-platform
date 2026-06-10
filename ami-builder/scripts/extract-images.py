#!/usr/bin/env python3
"""Extract all unique image: values from multi-document YAML on stdin."""
import sys, yaml

def find_images(obj):
    if isinstance(obj, dict):
        if 'image' in obj and isinstance(obj['image'], str):
            yield obj['image']
        for v in obj.values():
            yield from find_images(v)
    elif isinstance(obj, list):
        for item in obj:
            yield from find_images(item)

seen = set()
for doc in yaml.safe_load_all(sys.stdin):
    if doc is None:
        continue
    for img in find_images(doc):
        if img not in seen:
            seen.add(img)
            print(img)
