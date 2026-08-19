#!/usr/bin/env python3
"""mini_XCEPTION (Keras hdf5) -> BN 折叠 -> safetensors (MLX 布局) + numpy 参考前向。

键名对齐 Swift 侧 MLXNN 模块属性路径:
  stem1/stem2: 3x3 valid conv (BN 已折叠, 带 bias)
  m{i}res:     1x1 stride2 conv (BN 折叠)
  m{i}dw{j}:   depthwise 3x3 (无 bias)
  m{i}pw{j}:   pointwise 1x1 (BN 折叠, 带 bias)
  head:        3x3 same conv (原生 bias)
"""
import h5py, json, struct
import numpy as np

EPS = 1e-3
F = h5py.File('mini_xception.hdf5', 'r')['model_weights']

def W(layer, name):
    return np.array(F[layer][f'{layer}_1/{name}:0'], dtype=np.float32)

def bn(i):
    l = f'batch_normalization_{i}'
    g, b = W(l, 'gamma'), W(l, 'beta')
    m, v = W(l, 'moving_mean'), W(l, 'moving_variance')
    s = g / np.sqrt(v + EPS)
    return s, b - m * s   # y = x*s + t

def fold_conv(kernel, bn_idx):
    """kernel (H,W,I,O) + BN -> (kernel', bias)"""
    s, t = bn(bn_idx)
    return kernel * s.reshape(1, 1, 1, -1), t

# ---- 收集折叠后的权重 (Keras 布局) ----
P = {}  # name -> (kernel HWIO, bias or None)
P['stem1'] = fold_conv(W('conv2d_1', 'kernel'), 1)
P['stem2'] = fold_conv(W('conv2d_2', 'kernel'), 2)
# 模块 i: res=conv2d_{i+2}+bn_{3i}, sep{2i-1},sep{2i} + bn_{3i+1},bn_{3i+2}
for i in (1, 2, 3, 4):
    P[f'm{i}res'] = fold_conv(W(f'conv2d_{i+2}', 'kernel'), 3 * i)
    for j in (1, 2):
        sep = f'separable_conv2d_{2*(i-1)+j}'
        P[f'm{i}dw{j}'] = (W(sep, 'depthwise_kernel'), None)
        P[f'm{i}pw{j}'] = fold_conv(W(sep, 'pointwise_kernel'), 3 * i + j)
P['head'] = (W('conv2d_7', 'kernel'), W('conv2d_7', 'bias'))

# ---- numpy 参考前向 (NHWC) ----
def conv2d(x, k, b=None, stride=1, pad='valid', groups=1):
    H, Wd, I, O = k.shape
    if pad == 'same':  # Keras same: 不对称,右/下多补
        oh = -(-x.shape[1] // stride); ow = -(-x.shape[2] // stride)
        ph = max((oh - 1) * stride + H - x.shape[1], 0)
        pw = max((ow - 1) * stride + Wd - x.shape[2], 0)
        x = np.pad(x, ((0, 0), (ph // 2, ph - ph // 2), (pw // 2, pw - pw // 2), (0, 0)))
    n, h, w, c = x.shape
    oh, ow = (h - H) // stride + 1, (w - Wd) // stride + 1
    out = np.zeros((n, oh, ow, O * groups if groups > 1 else O), np.float32)
    if groups == 1:
        for dy in range(H):
            for dx in range(Wd):
                xs = x[:, dy:dy + oh * stride:stride, dx:dx + ow * stride:stride, :]
                out += xs @ k[dy, dx]
    else:  # depthwise: k (H,W,C,1), groups=C
        for dy in range(H):
            for dx in range(Wd):
                xs = x[:, dy:dy + oh * stride:stride, dx:dx + ow * stride:stride, :]
                out += xs * k[dy, dx, :, 0]
    if b is not None:
        out += b
    return out

def maxpool_same(x, size=3, stride=2):
    n, h, w, c = x.shape
    oh, ow = -(-h // stride), -(-w // stride)
    ph = max((oh - 1) * stride + size - h, 0)
    pw = max((ow - 1) * stride + size - w, 0)
    x = np.pad(x, ((0, 0), (ph // 2, ph - ph // 2), (pw // 2, pw - pw // 2), (0, 0)),
               constant_values=-np.inf)
    out = np.full((n, oh, ow, c), -np.inf, np.float32)
    for dy in range(size):
        for dx in range(size):
            out = np.maximum(out, x[:, dy:dy + oh * stride:stride, dx:dx + ow * stride:stride, :])
    return out

def forward(x):
    relu = lambda a: np.maximum(a, 0)
    x = relu(conv2d(x, *P['stem1']))
    x = relu(conv2d(x, *P['stem2']))
    for i in (1, 2, 3, 4):
        res = conv2d(x, *P[f'm{i}res'], stride=2, pad='same')
        x = conv2d(x, P[f'm{i}dw1'][0], pad='same', groups=x.shape[-1])
        x = relu(conv2d(x, *P[f'm{i}pw1']))
        x = conv2d(x, P[f'm{i}dw2'][0], pad='same', groups=x.shape[-1])
        x = conv2d(x, *P[f'm{i}pw2'])
        x = maxpool_same(x) + res
    x = conv2d(x, *P['head'], pad='same')
    x = x.mean(axis=(1, 2))                      # GAP
    e = np.exp(x - x.max(axis=-1, keepdims=True))
    return e / e.sum(axis=-1, keepdims=True)     # softmax

# ---- 导出 safetensors (MLX 布局: conv (O,H,W,I)) ----
def to_mlx(name, kernel):
    if 'dw' in name:                     # (H,W,C,1) -> (C,H,W,1)
        return np.ascontiguousarray(kernel.transpose(2, 0, 1, 3))
    return np.ascontiguousarray(kernel.transpose(3, 0, 1, 2))

tensors = {}
for name, (k, b) in P.items():
    tensors[f'{name}.weight'] = to_mlx(name, k)
    if b is not None:
        tensors[f'{name}.bias'] = np.ascontiguousarray(b)

def save_safetensors(path, tensors):
    header, offset, blobs = {}, 0, []
    for name in sorted(tensors):
        a = tensors[name].astype(np.float32)
        blobs.append(a.tobytes())
        header[name] = {'dtype': 'F32', 'shape': list(a.shape),
                        'data_offsets': [offset, offset + a.nbytes]}
        offset += a.nbytes
    hj = json.dumps(header, separators=(',', ':')).encode()
    with open(path, 'wb') as f:
        f.write(struct.pack('<Q', len(hj)))
        f.write(hj)
        for b in blobs:
            f.write(b)

if __name__ == '__main__':
    save_safetensors('emotion_mini_xception.safetensors', tensors)
    np.savez('folded.npz', **{n: v for n, v in tensors.items()})
    import os
    print('safetensors size:', os.path.getsize('emotion_mini_xception.safetensors'), 'bytes')
    # 固定测试向量: 决定性伪随机输入, [-1,1]
    rng = np.random.default_rng(42)
    x = (rng.random((1, 64, 64, 1), dtype=np.float32) - 0.5) * 2
    probs = forward(x)[0]
    labels = ['angry', 'disgust', 'fear', 'happy', 'sad', 'surprise', 'neutral']
    print('ref probs:', json.dumps(dict(zip(labels, probs.round(6).tolist()))))
    np.save('test_input.npy', x)
    np.save('test_probs.npy', probs)
