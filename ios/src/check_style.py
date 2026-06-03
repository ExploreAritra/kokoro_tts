import zipfile
import numpy as np

with zipfile.ZipFile('assets/voices.bin', 'r') as z:
    with z.open('af.npy') as f:
        data = np.load(f)
        print("Data shape:", data.shape)
        print("Max difference between slice 0 and 1:", np.max(np.abs(data[0] - data[1])))
        print("Max difference between slice 0 and 510:", np.max(np.abs(data[0] - data[510])))
