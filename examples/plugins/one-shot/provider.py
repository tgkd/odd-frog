#!/usr/bin/python3
import json
import sys

request = json.loads(sys.stdin.readline())
if request["method"] == "initialize":
    result = {"apiVersion": 2}
elif request["method"] == "query":
    text = request["params"]["input"]["query"]
    result = [{"id": "echo", "title": text or "Echo", "primary": {"kind": "copy", "value": text}}]
else:
    result = {}
print(json.dumps({"apiVersion": 2, "id": request["id"], "result": result}), flush=True)
