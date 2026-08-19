# 表情小模型 — mini-Xception (FER2013)

桌宠「摄像头在位感知」顺带认表情用的七分类模型:
`angry / disgust / fear / happy / sad / surprise / neutral`。

- **权重**:`emotion_mini_xception.safetensors`,**222KB**(fp32,约 5.8 万参数)。
- **来源**:[oarriaga/face_classification](https://github.com/oarriaga/face_classification)
  的 `fer2013_mini_XCEPTION.102-0.66.hdf5`(MIT 许可,FER2013 测试集 66% 准确率),
  sha256 `59534287fdfb125e30a94400296c25ea9f5d706fca93dd8adbbbed916799ea0e`。
- **转换**:`convert.py` 把所有 BatchNorm 折叠进卷积(推理端少一半层),权重转成
  MLX 的 (O,H,W,I) 布局,键名与 Swift 侧 `EmotionNet` 的模块路径一一对应。
  转换时和 TensorFlow 原模型对拍过:16 个随机输入最大偏差 1.4e-6,argmax 全一致。
- **推理**:`apps/desktop/pet-mac/Sources/EmotionNet.swift`,依赖
  [mlx-swift](https://github.com/ml-explore/mlx-swift)(exact 0.31.6)。输入 64×64
  灰度、[-1,1];Keras 偶数尺寸下不对称的 same-padding 池化在 Swift 里用手动
  -inf padding 复刻,逐像素一致。

## 重新生成

```sh
curl -LO https://github.com/oarriaga/face_classification/raw/master/trained_models/emotion_models/fer2013_mini_XCEPTION.102-0.66.hdf5
mv fer2013_mini_XCEPTION.102-0.66.hdf5 mini_xception.hdf5
python3 -m pip install h5py numpy
python3 convert.py   # 产出 emotion_mini_xception.safetensors + 参考输出
```

`convert.py` 里带一份 numpy 参考前向(和 hdf5 逐层同构),改 Swift 实现时用它
生成对拍向量。

## 隐私边界

模型完全在本地跑,挂在 `PresenceSensor` 的 30 秒抽帧上:帧 → 人脸框 → 64×64
灰度 → softmax,推理完帧即弃。跨出进程边界的只有 `sense_hints.json` 里的一个
表情标签 + 时间戳,和在位布尔同级(见 docs/FATIGUE.md)。
