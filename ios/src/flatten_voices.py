import zipfile
import numpy as np
import struct

with zipfile.ZipFile('assets/voices.bin', 'r') as z:
    npy_files = [f for f in z.infolist() if f.filename.endswith('.npy')]
    
    with open('assets/voices_flat.bin', 'wb') as out:
        # Header: magic bytes "KOKO", num_voices (int32)
        out.write(b'KOKO')
        out.write(struct.pack('<I', len(npy_files)))
        
        for info in npy_files:
            voice_name = info.filename.replace('.npy', '')
            name_bytes = voice_name.encode('utf-8')[:31]
            name_padded = name_bytes + b'\0' * (32 - len(name_bytes))
            out.write(name_padded)
            
            with z.open(info) as f:
                data = np.load(f)
                # data is shape (511, 1, 256), flat is 511*256 float32
                if data.shape != (511, 1, 256):
                    print(f"Warning: {voice_name} has shape {data.shape}")
                
                # Write 511 * 256 floats (little-endian)
                out.write(data.astype('<f4').tobytes())
                
print("Generated voices_flat.bin")
