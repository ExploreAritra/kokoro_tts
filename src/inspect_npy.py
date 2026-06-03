import zipfile
import numpy as np
import io

with zipfile.ZipFile('assets/voices.bin', 'r') as z:
    for info in z.infolist():
        if info.filename.endswith('.npy'):
            with z.open(info) as f:
                data = np.load(f)
                print(f"Voice {info.filename}: shape={data.shape}, dtype={data.dtype}")
            break
