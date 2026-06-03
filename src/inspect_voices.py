import json
import struct

try:
    with open('assets/voices.bin', 'rb') as f:
        data = f.read()
        print(f"Total size: {len(data)} bytes")
        
        # Is it a safetensors file?
        if len(data) > 8:
            header_len = struct.unpack('<Q', data[:8])[0]
            if 0 < header_len < 1000000 and header_len < len(data):
                try:
                    header = json.loads(data[8:8+header_len].decode('utf-8'))
                    print("Looks like safetensors!")
                    print(list(header.keys())[:10])
                except:
                    pass

        # Is it a custom JSON-separated file?
        # Try finding a JSON header if it starts with {
        if data.startswith(b'{'):
            end_idx = data.find(b'}')
            if end_idx != -1:
                header = json.loads(data[:end_idx+1].decode('utf-8'))
                print("Custom JSON header:", header)
                
        # What if it's just raw floats?
        print("First 32 bytes:", data[:32])

except Exception as e:
    print("Error:", e)
