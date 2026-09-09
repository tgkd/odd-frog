#!/usr/bin/python3
"""Independent Python example: API 2 only, no Swift SDK or host feature code."""
import json
import pathlib
import sys

count = 0

def send(**message):
    print(json.dumps(dict(apiVersion=2, **message)), flush=True)

for line in sys.stdin:
    request = json.loads(line)
    method = request.get("method")
    if method == "shutdown":
        break
    if method == "cancel":
        continue
    params = request.get("params", {})
    settings = params.get("context", {}).get("settings", {})
    try:
        if method in ("initialize", "settings"):
            result = {"apiVersion": 2}
        elif method == "catalog":
            result = [{"id": "counter", "title": settings.get("label", "Count"),
                       "subtitle": str(count), "history": True,
                       "argument": {"placeholder": "Optional note", "optional": True},
                       "primary": {"kind": "callback", "value": "increment", "payload": {"source": "catalog"}}}]
        elif method == "activate":
            if params["input"]["actionID"] != "increment":
                raise ValueError("Unknown callback")
            count += settings.get("step", 1)
            result = {"refreshCatalog": True, "refreshQuery": False}
            if settings.get("notify", True):
                result["notification"] = str(count) + " " + (params["input"].get("argument") or "")
        else:
            raise ValueError("Unknown method")
        send(id=request["id"], result=result)
    except Exception as error:
        send(id=request["id"], error={"code": "operation", "message": str(error)})
