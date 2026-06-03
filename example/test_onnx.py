import onnxruntime as ort
session = ort.InferenceSession("assets/kokoro-v0_19.onnx")
for i, input in enumerate(session.get_inputs()):
    print(f"Input {i}: name='{input.name}', shape={input.shape}, type={input.type}")
for i, output in enumerate(session.get_outputs()):
    print(f"Output {i}: name='{output.name}', shape={output.shape}, type={output.type}")
