import CoreImage
import Foundation
import MLX
import MLXNN
import Vision

/// 表情七分类。标签顺序 = FER2013 训练顺序,不能改。
enum Emotion: String, CaseIterable {
    case angry, disgust, fear, happy, sad, surprise, neutral
}

/// mini-Xception(FER2013,~6 万参数)的 MLX 前向。权重来自
/// oarriaga/face_classification(MIT),经 model/emotion/convert.py 折叠
/// BatchNorm 后存成 222KB 的 safetensors,随 app 打包。
///
/// 输入 (1,64,64,1) 灰度,值域 [-1,1];输出 7 类 softmax 概率。
/// 与原 Keras 模型的偏差 <1e-5(转换脚本里与 TensorFlow 对拍过)。
final class EmotionNet: Module {
    let stem1 = Conv2d(inputChannels: 1, outputChannels: 8, kernelSize: 3, bias: true)
    let stem2 = Conv2d(inputChannels: 8, outputChannels: 8, kernelSize: 3, bias: true)

    let m1res = Conv2d(inputChannels: 8, outputChannels: 16, kernelSize: 1, stride: 2, bias: true)
    let m1dw1 = Conv2d(inputChannels: 8, outputChannels: 8, kernelSize: 3, padding: 1, groups: 8, bias: false)
    let m1pw1 = Conv2d(inputChannels: 8, outputChannels: 16, kernelSize: 1, bias: true)
    let m1dw2 = Conv2d(inputChannels: 16, outputChannels: 16, kernelSize: 3, padding: 1, groups: 16, bias: false)
    let m1pw2 = Conv2d(inputChannels: 16, outputChannels: 16, kernelSize: 1, bias: true)

    let m2res = Conv2d(inputChannels: 16, outputChannels: 32, kernelSize: 1, stride: 2, bias: true)
    let m2dw1 = Conv2d(inputChannels: 16, outputChannels: 16, kernelSize: 3, padding: 1, groups: 16, bias: false)
    let m2pw1 = Conv2d(inputChannels: 16, outputChannels: 32, kernelSize: 1, bias: true)
    let m2dw2 = Conv2d(inputChannels: 32, outputChannels: 32, kernelSize: 3, padding: 1, groups: 32, bias: false)
    let m2pw2 = Conv2d(inputChannels: 32, outputChannels: 32, kernelSize: 1, bias: true)

    let m3res = Conv2d(inputChannels: 32, outputChannels: 64, kernelSize: 1, stride: 2, bias: true)
    let m3dw1 = Conv2d(inputChannels: 32, outputChannels: 32, kernelSize: 3, padding: 1, groups: 32, bias: false)
    let m3pw1 = Conv2d(inputChannels: 32, outputChannels: 64, kernelSize: 1, bias: true)
    let m3dw2 = Conv2d(inputChannels: 64, outputChannels: 64, kernelSize: 3, padding: 1, groups: 64, bias: false)
    let m3pw2 = Conv2d(inputChannels: 64, outputChannels: 64, kernelSize: 1, bias: true)

    let m4res = Conv2d(inputChannels: 64, outputChannels: 128, kernelSize: 1, stride: 2, bias: true)
    let m4dw1 = Conv2d(inputChannels: 64, outputChannels: 64, kernelSize: 3, padding: 1, groups: 64, bias: false)
    let m4pw1 = Conv2d(inputChannels: 64, outputChannels: 128, kernelSize: 1, bias: true)
    let m4dw2 = Conv2d(inputChannels: 128, outputChannels: 128, kernelSize: 3, padding: 1, groups: 128, bias: false)
    let m4pw2 = Conv2d(inputChannels: 128, outputChannels: 128, kernelSize: 1, bias: true)

    let head = Conv2d(inputChannels: 128, outputChannels: 7, kernelSize: 3, padding: 1, bias: true)

    /// Keras 的 same-padding 在偶数尺寸上不对称(只补右/下),MLX 的池化
    /// 只会对称补,所以这里手动补 -inf 再做 valid 池化,保证逐像素一致。
    private func maxPoolSame3x3s2(_ x: MLXArray) -> MLXArray {
        let h = x.dim(1), w = x.dim(2)
        let ph = max(((h + 1) / 2 - 1) * 2 + 3 - h, 0)
        let pw = max(((w + 1) / 2 - 1) * 2 + 3 - w, 0)
        let padded = MLX.padded(
            x,
            widths: [[0, 0], [ph / 2, ph - ph / 2], [pw / 2, pw - pw / 2], [0, 0]],
            value: MLXArray(-Float.infinity))
        return MaxPool2d(kernelSize: 3, stride: 2)(padded)
    }

    private func block(
        _ x: MLXArray, _ res: Conv2d, _ dw1: Conv2d, _ pw1: Conv2d, _ dw2: Conv2d, _ pw2: Conv2d
    ) -> MLXArray {
        let shortcut = res(x)
        var h = relu(pw1(dw1(x)))
        h = pw2(dw2(h))
        return maxPoolSame3x3s2(h) + shortcut
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = relu(stem1(x))
        h = relu(stem2(h))
        h = block(h, m1res, m1dw1, m1pw1, m1dw2, m1pw2)
        h = block(h, m2res, m2dw1, m2pw1, m2dw2, m2pw2)
        h = block(h, m3res, m3dw1, m3pw1, m3dw2, m3pw2)
        h = block(h, m4res, m4dw1, m4pw1, m4dw2, m4pw2)
        h = head(h).mean(axes: [1, 2])
        return softmax(h, axis: -1)
    }

    /// 从 safetensors 加载权重(键名与上面的属性路径一一对应,verify: .all
    /// 保证少一个键、错一个形状都会当场抛错,而不是带着随机权重上线)。
    static func load(url: URL) throws -> EmotionNet {
        let net = EmotionNet()
        let weights = try MLX.loadArrays(url: url)
        try net.update(parameters: ModuleParameters.unflattened(weights), verify: .all)
        MLX.eval(net.parameters())
        return net
    }
}

/// 表情分类器:人脸框 → 64×64 灰度 → EmotionNet → 稳定后的标签。
/// 单帧 FER 很抖,这里要求 top-1 概率过阈值才报,否则报 nil(宁缺毋滥,
/// 和活动分类的 unknown 语义一致)。
final class EmotionClassifier {
    private let net: EmotionNet
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    /// FER2013 上 66% 的七分类模型,低于这个置信度的判定不值得跨边界。
    private let minConfidence: Float = 0.35

    convenience init?() {
        guard let url = Bundle.main.url(
            forResource: "emotion_mini_xception", withExtension: "safetensors")
        else { return nil }
        self.init(weightsURL: url)
    }

    init?(weightsURL: URL) {
        guard let net = try? EmotionNet.load(url: weightsURL) else { return nil }
        self.net = net
    }

    /// 帧和人脸框进,标签出;图像数据在本函数栈上生灭,不落盘不出进程。
    func classify(pixelBuffer: CVPixelBuffer, face: VNFaceObservation) -> (Emotion, Float)? {
        guard let gray = grayFace(pixelBuffer: pixelBuffer, face: face) else { return nil }
        // 与训练一致的预处理:x/255 → -0.5 → ×2,落在 [-1,1]
        let floats = gray.map { Float($0) / 255.0 * 2.0 - 1.0 }
        let input = MLXArray(floats, [1, 64, 64, 1])
        let probs = net(input).asArray(Float.self)
        guard probs.count == Emotion.allCases.count,
              let best = probs.indices.max(by: { probs[$0] < probs[$1] }),
              probs[best] >= minConfidence
        else { return nil }
        return (Emotion.allCases[best], probs[best])
    }

    /// 人脸框外扩两成(FER2013 的脸带额头和下巴),裁剪缩放到 64×64 灰度。
    /// Vision 的框和 CIImage 同为左下原点归一化坐标,不需要翻转。
    private func grayFace(pixelBuffer: CVPixelBuffer, face: VNFaceObservation) -> [UInt8]? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let bounds = image.extent
        var rect = CGRect(
            x: face.boundingBox.origin.x * bounds.width,
            y: face.boundingBox.origin.y * bounds.height,
            width: face.boundingBox.width * bounds.width,
            height: face.boundingBox.height * bounds.height)
        rect = rect.insetBy(dx: -rect.width * 0.2, dy: -rect.height * 0.2)
            .intersection(bounds)
        guard rect.width >= 24, rect.height >= 24 else { return nil }

        let scaled = image
            .cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY)
                .concatenating(CGAffineTransform(scaleX: 64 / rect.width, y: 64 / rect.height)))
        var pixels = [UInt8](repeating: 0, count: 64 * 64)
        ciContext.render(
            scaled, toBitmap: &pixels, rowBytes: 64,
            bounds: CGRect(x: 0, y: 0, width: 64, height: 64),
            format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
        // CoreImage 的 y 轴朝上,位图行序朝下,渲染结果已是常规行序;
        // FER 训练数据也是常规行序,这里方向一致。
        return pixels
    }
}
