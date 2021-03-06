/* Copyright (c) 2017 Baidu, Inc. All Rights Reserved.
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 ==============================================================================*/

import MDL
import UIKit
import Metal
import MetalKit
import CoreMedia
import MetalPerformanceShaders

enum GPUModelType {
    case squeezeNet, mobileNet
}
var gpuModelType: GPUModelType = .squeezeNet

class GPUNetViewController: UIViewController {
    
    @IBOutlet weak var videoView: UIView!
    @IBOutlet weak var resultLabel: UILabel!
    let labels = ImageNetLabels()
    let device = MTLCreateSystemDefaultDevice()!
    var textureLoader: MTKTextureLoader!
    var commandQueue: MTLCommandQueue!
    var net: MDLGPUNet?
    var isFirstIn = true
    var videoCapture: VideoCapture!
    var startupGroup = DispatchGroup()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        commandQueue = device.makeCommandQueue()
        textureLoader = MTKTextureLoader(device: device)
        
        startupGroup.enter()
        initializeVideoCapture {
            self.startupGroup.leave()
        }
        
        startupGroup.enter()
        initializeNet {
            self.startupGroup.leave()
        }
        
       startupGroup.notify(queue: .main) {
            self.videoCapture.start()
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        videoCapture.stop()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !isFirstIn {
            videoCapture.start()
        }
        isFirstIn = false
    }

    func initializeVideoCapture(completion: @escaping () -> Void){
        videoCapture = VideoCapture(device: device)
        videoCapture.delegate = self
        videoCapture.fps = 10
        videoCapture.setUp { (success) in
            if let previewLayer = self.videoCapture.previewLayer{
                self.videoView.layer.insertSublayer(previewLayer, at: 0)
                previewLayer.frame = self.videoView.bounds
          }
            completion()
        }
    }
    
    
    func initializeNet(completion: @escaping () -> Void) {
        guard MPSSupportsMTLDevice(device) else {
            fatalError("设备不支持")
        }
        
        let modelPath: String
        if gpuModelType == .mobileNet {
            modelPath = Bundle.main.path(forResource: "mobileNetModel", ofType: "json") ?! "can't find mobileNetModel json"
        }else if gpuModelType == .squeezeNet{
            modelPath = Bundle.main.path(forResource: "squeezenet", ofType: "json") ?! "can't find squeezenet json"
        }else{
            fatalError("undefine type")
        }
        
        do{
            let ker: MetalKernel?
            if gpuModelType == .mobileNet {
                ker = MobileNetPreprocessing(device: device)
            }else if gpuModelType == .squeezeNet{
                ker = SqueezeNetPreprocess(device: device)
            }else{
                ker = nil
            }
            
            try MDLGPUNet.share.load(device: device, modelPath: modelPath, preProcessKernel: ker, commandQueue: commandQueue, para: { (matrixName, count) -> NetParameterData? in
                let bundle: Bundle
                if gpuModelType == .mobileNet{
                    let bundlePath = Bundle.main.path(forResource: "MobileNetParameters", ofType: "bundle") ?! "can't find MobileNetParameters.bundle"
                    bundle = Bundle.init(path: bundlePath) ?! "can't load MobileNetParameters.bundle"
                }else if gpuModelType == .squeezeNet{
                    let bundlePath = Bundle.main.path(forResource: "SqueezenetParameters", ofType: "bundle") ?! "can't find SqueezenetParameters.bundle"
                    bundle = Bundle.init(path: bundlePath) ?! "can't load SqueezenetParameters.bundle"
                }else{
                    fatalError("undefine type")
                }
                return NetParameterLoaderBundle(name: matrixName, count: count, ext: "bin", bundle: bundle)
            })
        }catch {
            print(error)
            switch error {
            case NetError.loaderError(message: let message):
                print(message)
            case NetError.modelDataError(message: let message):
                print(message)
            default:
                break
            }
        }
        completion()
    }
    
    func predict(texture: MTLTexture) {
        do {
            try MDLGPUNet.share.predict(inTexture: texture, completion: { (result) in
                self.show(result: result)
            })
        } catch  {
            print(error)
        }
    }
    
    func show(result: MDLNetResult) {
        var s: [String] = ["耗时: \(result.elapsedTime) s"]
        result.result.top(r: 5).enumerated().forEach{
            s.append(String(format: "%d: %@ (%3.2f%%)", $0 + 1, labels[$1.0], $1.1 * 100))
        }
        resultLabel.text = s.joined(separator: "\n\n")
    }
}

extension GPUNetViewController: VideoCaptureDelegate{
    func videoCapture(_ capture: VideoCapture, didCaptureVideoTexture texture: MTLTexture?, timestamp: CMTime) {
        if let inTexture = texture {
            predict(texture: inTexture)
        }
    }
    
    func videoCapture(_ capture: VideoCapture, didCapturePhotoTexture texture: MTLTexture?, previewImage: UIImage?) {
    }
}




