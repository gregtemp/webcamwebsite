import cv2
import os
import signal
import threading
from flask import Flask, Response, jsonify

app = Flask(__name__)

# Cache of open captures, protected per-index with locks
captures = {}
capture_locks = {}
global_lock = threading.Lock()


def get_lock(index):
    with global_lock:
        if index not in capture_locks:
            capture_locks[index] = threading.Lock()
        return capture_locks[index]


def open_capture(index):
    cap = cv2.VideoCapture(index, cv2.CAP_AVFOUNDATION)
    if not cap.isOpened():
        cap = cv2.VideoCapture(index)
    return cap


def enumerate_cameras():
    cameras = []
    for i in range(10):
        cap = open_capture(i)
        if cap.isOpened():
            cameras.append({"index": i, "name": f"Camera {i}"})
            cap.release()
    return cameras


def generate_frames(index):
    lock = get_lock(index)
    with lock:
        cap = open_capture(index)
        if not cap.isOpened():
            return
        try:
            while True:
                ret, frame = cap.read()
                if not ret:
                    break
                _, jpeg = cv2.imencode(".jpg", frame)
                yield (
                    b"--frame\r\n"
                    b"Content-Type: image/jpeg\r\n\r\n"
                    + jpeg.tobytes()
                    + b"\r\n"
                )
        finally:
            cap.release()


HTML = """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Webcam Stream</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { background: #000; width: 100vw; height: 100vh; overflow: hidden; }
  #stream { width: 100%; height: 100%; object-fit: cover; display: block; }
  #controls {
    position: fixed;
    top: 12px;
    right: 12px;
    background: rgba(0,0,0,0.55);
    padding: 8px 12px;
    border-radius: 6px;
  }
  #controls label { color: #fff; font-family: sans-serif; font-size: 14px; margin-right: 8px; }
  #camera-select { font-size: 14px; padding: 2px 4px; }
  #kill-btn {
    margin-left: 12px;
    background: #c0392b;
    color: #fff;
    border: none;
    border-radius: 4px;
    padding: 3px 10px;
    font-size: 14px;
    cursor: pointer;
  }
  #kill-btn:hover { background: #e74c3c; }
</style>
</head>
<body>
<img id="stream" src="/stream/0" alt="webcam stream">
<div id="controls">
  <label for="camera-select">Camera:</label>
  <select id="camera-select"></select>
  <button id="kill-btn" title="Kill server">Kill</button>
</div>
<script>
  const img = document.getElementById('stream');
  const sel = document.getElementById('camera-select');

  fetch('/cameras')
    .then(r => r.json())
    .then(cameras => {
      cameras.forEach(cam => {
        const opt = document.createElement('option');
        opt.value = cam.index;
        opt.textContent = cam.name;
        sel.appendChild(opt);
      });
    });

  sel.addEventListener('change', () => {
    img.src = '/stream/' + sel.value;
  });

  document.getElementById('kill-btn').addEventListener('click', () => {
    if (confirm('Kill the server?')) fetch('/kill', {method: 'POST'});
  });
</script>
</body>
</html>
"""


@app.route("/")
def index():
    return HTML, 200, {"Content-Type": "text/html; charset=utf-8"}


@app.route("/cameras")
def cameras():
    return jsonify(enumerate_cameras())


@app.route("/stream/<int:index>")
def stream(index):
    return Response(
        generate_frames(index),
        mimetype="multipart/x-mixed-replace; boundary=frame",
    )


@app.route("/kill", methods=["POST"])
def kill():
    threading.Timer(0.1, lambda: os.kill(os.getpid(), signal.SIGTERM)).start()
    return jsonify({"status": "shutting down"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, threaded=True)
