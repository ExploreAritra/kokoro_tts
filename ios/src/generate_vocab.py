import json

with open('tokenizer.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

vocab = data['model']['vocab']
cpp_code = """#ifndef KOKORO_VOCAB_H
#define KOKORO_VOCAB_H

#include <unordered_map>
#include <string>
#include <cstdint>

static const std::unordered_map<std::string, int64_t> KOKORO_VOCAB = {
"""

for k, v in vocab.items():
    # escape quotes and backslashes
    k_escaped = k.replace('\\', '\\\\').replace('"', '\\"')
    cpp_code += f'    {{"{k_escaped}", {v}}},\n'

cpp_code += """};

#endif // KOKORO_VOCAB_H
"""

with open('kokoro_vocab.h', 'w', encoding='utf-8') as f:
    f.write(cpp_code)

print("kokoro_vocab.h generated!")
