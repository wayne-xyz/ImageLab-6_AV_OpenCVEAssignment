//
//  VideoAnalgesic.swift
//  VideoAnalgesicTest
//
//  Created by Eric Larson .
//  Copyright (c) Eric Larson. All rights reserved.
//

import Foundation
import AVFoundation
import CoreImage
import MetalKit

//typealias ProcessBlock = (_ imageInput : CIImage ) -> (CIImage)

class VideoAnalgesic: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    // AV session properties
    private var captureSessionQueue: DispatchQueue
    private var devicePosition: AVCaptureDevice.Position
    private var videoDevice: AVCaptureDevice? = nil
    private var captureSession:AVCaptureSession? = nil
    private var preset:String? = AVCaptureSession.Preset.medium.rawValue
    private var captureOrient:AVCaptureVideoOrientation? = nil
    
    // CI Properties
    private var ciContext:CIContext!
    private var processBlock:ProcessBlock? = nil
    
    // public access properties
    var transform : CGAffineTransform = CGAffineTransform.identity
    var ciOrientation = 5
    
    // metal stuff
    private var metalLayer: CAMetalLayer!
    private var metalDevice: MTLDevice!
    var commandQueue: MTLCommandQueue!
    
    // read only properties
    private var _isRunning:Bool = false
    var isRunning:Bool {
        get {
            return self._isRunning
        }
    }
    
    // for setting the filters pipeline (r whatever processing you are doing)
    func setProcessingBlock(newProcessBlock: @escaping ProcessBlock)
    {
        self.processBlock = newProcessBlock // to find out: does Swift do a deep copy??
    }
    
    
    
    func shutdown(){
        self.processBlock = nil
        self.stop()
    }
    
    init(mainView:UIView) {
        
        
        // create a serial queue
        captureSessionQueue = DispatchQueue(label: "capture_session_queue")
        devicePosition = AVCaptureDevice.Position.back
        
        
        // because the native video image from the back camera is in UIDeviceOrientationLandscapeLeft (i.e. the home button is on the right), we need to apply a clockwise 90 degree transform so that we can draw the video preview as if we were in a landscape-oriented view; if you're using the front camera and you want to have a mirrored preview (so that the user is seeing themselves in the mirror), you need to apply an additional horizontal flip (by concatenating CGAffineTransformMakeScale(-1.0, 1.0) to the rotation transform)
        transform = CGAffineTransform.identity
        transform = transform.rotated(by: CGFloat(Double.pi/2))
        transform = transform.concatenating(CGAffineTransform(scaleX: 1.2, y: 1.35))
        
        
        // get device
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("GPU not available") }
        metalDevice = device
        
        // set Metal context on GPU
        ciContext = CIContext(mtlDevice: metalDevice)
        
        //setup layer (in the back of the views)
        metalLayer = CAMetalLayer()
        metalLayer.device = self.metalDevice
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.transform = CATransform3DMakeAffineTransform(transform)
        metalLayer.frame = CGRect(origin: .zero, size: mainView.layer.frame.size)//mainView.layer.frame
        //metalLayer.position = CGPoint(x: 0.0, y: 0.0)
        mainView.layer.insertSublayer(metalLayer, at:0)
        
        commandQueue = self.metalDevice.makeCommandQueue()

        super.init()
        
        
    }
    
    private func start_internal()->(){
        
        if (captureSession != nil){
            return; // we are already running, just return
        }
        
//        NotificationCenter.default.addObserver(self,
//                                               selector:#selector(VideoAnalgesic.updateOrientation),
//                                               name:NSNotification.Name(rawValue: "UIApplicationDidChangeStatusBarOrientationNotification"),
//                                               object:nil)
        
        captureSessionQueue.async(){
            let error:Error? = nil;
            let position = self.devicePosition;
            self.videoDevice = nil;
            
            let deviceDiscoverySession = AVCaptureDevice.DiscoverySession.init(deviceTypes: [AVCaptureDevice.DeviceType.builtInWideAngleCamera],
                                                                               mediaType: AVMediaType.video,
                                                                               position: AVCaptureDevice.Position.unspecified)
            
            for device in deviceDiscoverySession.devices {
                if device.position == position {
                    self.videoDevice = device
                    break;
                }
            }
            
            
            // obtain device input
            let videoDeviceInput: AVCaptureDeviceInput = (try! AVCaptureDeviceInput(device: self.videoDevice!))
            
            if (error != nil)
            {
                NSLog("Unable to obtain video device input, error: \(String(describing: error))");
                return;
            }
            
            if (self.videoDevice?.supportsSessionPreset(AVCaptureSession.Preset(rawValue: self.preset!))==false)
            {
                NSLog("Capture session preset not supported by video device: \(String(describing: self.preset))");
                return;
            }
            
            // create the capture session
            self.captureSession = AVCaptureSession()
            self.captureSession!.sessionPreset = AVCaptureSession.Preset(rawValue: self.preset!);
            
            // create and configure video data output
            let videoDataOutput = AVCaptureVideoDataOutput()
            videoDataOutput.alwaysDiscardsLateVideoFrames = true;
            videoDataOutput.setSampleBufferDelegate(self, queue:self.captureSessionQueue)
            
            // begin configure capture session
            if let capture = self.captureSession{
                capture.beginConfiguration()
                
                if (!capture.canAddOutput(videoDataOutput))
                {
                    return;
                }
                
                // connect the video device input and video data and still image outputs
                capture.addInput(videoDeviceInput as AVCaptureInput)
                capture.addOutput(videoDataOutput)
                
                capture.commitConfiguration()
                
                // then start everything
                capture.startRunning()
            }
            
            //self.updateOrientation()
        }
    }
    
    
    
    func start(){
        
        // see if we have any video device
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession.init(deviceTypes: [AVCaptureDevice.DeviceType.builtInWideAngleCamera],
                                                                           mediaType: AVMediaType.video,
                                                                           position: AVCaptureDevice.Position.unspecified)
        
        if (deviceDiscoverySession.devices.count > 0)
        {
            self.start_internal()
            self._isRunning = true
        }
        else{
            NSLog("Could not start Analgesic video manager");
            NSLog("Be sure that you are running from an iOS device, not the simulator")
            self._isRunning = false;
        }
        
    }
    
    func stop(){
        if (self.captureSession==nil || self.captureSession!.isRunning==false){
            return
        }
        
        self.captureSession!.stopRunning()
        
//        NotificationCenter.default.removeObserver(self,
//                                                  name: NSNotification.Name(rawValue: "UIApplicationDidChangeStatusBarOrientationNotification"), object: nil)
        
        self.captureSessionQueue.sync(){
            NSLog("waiting for capture session to end")
        }
        NSLog("Done!")
        
        self.captureSession = nil
        self.videoDevice = nil
        self._isRunning = false
        
    }
    
    // video buffer delegate
    func captureOutput(_ captureOutput: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let sourceImage = CIImage(cvPixelBuffer: imageBuffer! as CVPixelBuffer, options:nil)
        
        
        // run through a filter
        var filteredImage:CIImage! = nil;
        
        if(self.processBlock != nil){
            filteredImage=self.processBlock!(sourceImage)
        }
        
//        let sourceExtent:CGRect = sourceImage.extent
//        let previewExtent:CGRect = self.metalLayer.frame
//
//        let sourceAspect = sourceExtent.size.width / sourceExtent.size.height;
//        let previewAspect = previewExtent.size.width  / previewExtent.size.height
//
//        // we want to maintain the aspect ratio of the screen size, so we clip the video image
//        var drawRect = sourceExtent
//
//        if (sourceAspect > previewAspect)
//        {
//            // use full height of the video image, and center crop the width
//            drawRect.origin.x += (drawRect.size.width - drawRect.size.height * previewAspect) / 2.0;
//            drawRect.size.width = drawRect.size.height * previewAspect;
//        }
//        else
//        {
//            // use full width of the video image, and center crop the height
//            drawRect.origin.y += (drawRect.size.height - drawRect.size.width / previewAspect) / 2.0;
//            drawRect.size.height = drawRect.size.width / previewAspect;
//        }
        
        if (filteredImage != nil)
        {
            DispatchQueue.main.async(){
                guard let drawable = self.metalLayer?.nextDrawable() else { return }
                let cSpace = CGColorSpaceCreateDeviceRGB()
                
                // render image to drawable display
                if let commandBuffer = self.commandQueue.makeCommandBuffer(){
                    self.ciContext.render(filteredImage, to: drawable.texture,
                                          commandBuffer: commandBuffer,
                                          bounds: CGRect(origin: .zero, size: self.metalLayer.drawableSize),
                                          colorSpace: cSpace)
                    commandBuffer.present(drawable)
                    commandBuffer.commit()
                }
                
            }
        }
        
    }
    
    func toggleFlash()->(Bool){
        var isOverHeating = false
        if let device = self.videoDevice{
            if (device.hasTorch && self.devicePosition == AVCaptureDevice.Position.back) {
                do {
                    try device.lockForConfiguration()
                } catch _ {
                }
                if (device.torchMode == AVCaptureDevice.TorchMode.on) {
                    device.torchMode = AVCaptureDevice.TorchMode.off
                } else {
                    do {
                        try device.setTorchModeOn(level: 1.0)
                        isOverHeating = false
                    } catch _ {
                        isOverHeating = true
                    }
                }
                device.unlockForConfiguration()
            }
        }
        return isOverHeating
    }
    
    func setFPS(desiredFrameRate:Double){
        if let device = self.videoDevice{
            do {
                try device.lockForConfiguration()
            } catch _ {
            }
            
            // set to FPS
            let format = device.activeFormat
            let time:CMTime = CMTimeMake(value: 1, timescale: Int32(desiredFrameRate))
            
            for range in format.videoSupportedFrameRateRanges {
                if range.minFrameRate <= (desiredFrameRate + 0.0001) && range.maxFrameRate >= (desiredFrameRate - 0.0001) {
                    device.activeVideoMaxFrameDuration = time
                    device.activeVideoMinFrameDuration = time
                    print("Changed FPS to \(desiredFrameRate)")
                    break
                }
                
            }
            device.unlockForConfiguration()
        }
        
        
    }
    
    
    func turnOnFlashwithLevel(_ level:Float) -> (Bool){
        var isOverHeating = false
        if let device = self.videoDevice{
            if (device.hasTorch && self.devicePosition == AVCaptureDevice.Position.back && level>0 && level<=1) {
                do {
                    try device.lockForConfiguration()
                } catch _ {
                }
                do {
                    try device.setTorchModeOn(level: level)
                    isOverHeating = false
                } catch _ {
                    isOverHeating = true
                }
                device.unlockForConfiguration()
            }
        }
        return isOverHeating
    }
    
    
    func turnOffFlash(){
        if let device = self.videoDevice{
            if (device.hasTorch && device.torchMode == AVCaptureDevice.TorchMode.on) {
                do {
                    try device.lockForConfiguration()
                } catch _ {
                }
                device.torchMode = AVCaptureDevice.TorchMode.off
                device.unlockForConfiguration()
            }
        }
    }
    
    // for setting the camera we should use
    func setCameraPosition(position: AVCaptureDevice.Position){
        // AVCaptureDevicePosition.Back
        // AVCaptureDevicePosition.Front
        if(position != self.devicePosition){
            self.devicePosition = position;
            if(self.isRunning){
                self.stop()
                self.start()
            }
        }
    }
    
    // for setting the camera we should use
    func toggleCameraPosition(){
        // AVCaptureDevicePosition.Back
        // AVCaptureDevicePosition.Front
        switch self.devicePosition{
        case AVCaptureDevice.Position.back:
            self.devicePosition = AVCaptureDevice.Position.front
        case AVCaptureDevice.Position.front:
            self.devicePosition = AVCaptureDevice.Position.back
        default:
            self.devicePosition = AVCaptureDevice.Position.front
        }
        
        if(self.isRunning){
            self.stop()
            self.start()
        }
    }
    
    // for setting the image quality
    func setPreset(_ preset: String){
        // AVCaptureSessionPresetPhoto
        // AVCaptureSessionPresetHigh
        // AVCaptureSessionPresetMedium <- default
        // AVCaptureSessionPresetLow
        // AVCaptureSessionPreset320x240
        // AVCaptureSessionPreset352x288
        // AVCaptureSessionPreset640x480
        // AVCaptureSessionPreset960x540
        // AVCaptureSessionPreset1280x720
        // AVCaptureSessionPresetiFrame960x540
        // AVCaptureSessionPresetiFrame1280x720
        if(preset != self.preset){
            self.preset = preset;
            if(self.isRunning){
                self.stop()
                self.start()
            }
        }
    }
    
    func getCIContext()->(CIContext?){
        if let context = self.ciContext{
            return context;
        }
        return nil;
    }
    
    func getImageOrientationFromUIOrientation(_ interfaceOrientation:UIInterfaceOrientation)->(Int){
        var ciOrientation = 1;
        
        switch interfaceOrientation{
        case UIInterfaceOrientation.portrait:
            ciOrientation = 5
        case UIInterfaceOrientation.portraitUpsideDown:
            ciOrientation = 7
        case UIInterfaceOrientation.landscapeLeft:
            ciOrientation = 1
        case UIInterfaceOrientation.landscapeRight:
            ciOrientation = 3
        default:
            ciOrientation = 1
        }
        
        return ciOrientation
    }
    
//    @objc func updateOrientation(){
//        if !self._isRunning{
//            return
//        }
//
//        DispatchQueue.main.async(){
//
//            switch (UIDevice.current.orientation, self.videoDevice!.position){
//            case (UIDeviceOrientation.landscapeRight, AVCaptureDevice.Position.back):
//                self.ciOrientation = 3
//                self.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi))
//            case (UIDeviceOrientation.landscapeLeft, AVCaptureDevice.Position.back):
//                self.ciOrientation = 1
//                self.transform = CGAffineTransform.identity
//            case (UIDeviceOrientation.landscapeLeft, AVCaptureDevice.Position.front):
//                self.ciOrientation = 3
//                self.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi))
//                self.transform = self.transform.concatenating(CGAffineTransform(scaleX: -1.0, y: 1.0))
//            case (UIDeviceOrientation.landscapeRight, AVCaptureDevice.Position.front):
//                self.ciOrientation = 1
//                self.transform = CGAffineTransform.identity
//                self.transform = self.transform.concatenating(CGAffineTransform(scaleX: -1.0, y: 1.0))
//            case (UIDeviceOrientation.portraitUpsideDown, AVCaptureDevice.Position.back):
//                self.ciOrientation = 7
//                self.transform = CGAffineTransform(rotationAngle: CGFloat(3*Double.pi/2))
//            case (UIDeviceOrientation.portraitUpsideDown, AVCaptureDevice.Position.front):
//                self.ciOrientation = 7
//                self.transform = CGAffineTransform(rotationAngle: CGFloat(3*Double.pi/2))
//                self.transform = self.transform.concatenating(CGAffineTransform(scaleX: -1.0, y: 1.0))
//            case (UIDeviceOrientation.portrait, AVCaptureDevice.Position.back):
//                self.ciOrientation = 5
//                self.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi/2))
//            case (UIDeviceOrientation.portrait, AVCaptureDevice.Position.front):
//                self.ciOrientation = 5
//                self.transform = CGAffineTransform(rotationAngle: CGFloat(-Double.pi/2))
//                self.transform = self.transform.concatenating(CGAffineTransform(scaleX: -1.0, y: -1.0))
//            default:
//                self.ciOrientation = 5
//                self.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi/2))
//            }
//            self.transform = self.transform.concatenating(CGAffineTransform(scaleX: 1.2, y: 1.35))
//            self.metalLayer.transform = CATransform3DMakeAffineTransform(self.transform)
//
//        }
//    }
    
    
}

