//
//  VisionAnalgesic.swift
//  ImageLab
//
//  Created by Eric Cooper Larson on 10/11/23.
//  Copyright © 2023 Eric Larson. All rights reserved.
//

import Vision
import MetalKit
import AVFoundation
import CoreImage


typealias ProcessBlock = (_ imageInput : CIImage ) -> (CIImage)
typealias VisionHandler = (_ results:[VNFaceObservation]) -> Void

/// A vision model for easily capturing video from the cameras and rendering processed images to an MTKView. VisionAnagesic class requires that a MetalView (import MetalKit) is used and passed into the initializer. Class will keep a weak reference to this view. All rendered video will go to this view. Before deallocating the MTKView, developers should call the shutdown method.
class VisionAnalgesic:NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, MTKViewDelegate {
    
    //MARK: Properties
    // AV session properties
    private var videoDevice: AVCaptureDevice? = nil
    private var preset:String? = AVCaptureSession.Preset.high.rawValue
    private var captureOrient:AVCaptureVideoOrientation? = nil
    private var devicePosition: AVCaptureDevice.Position
    
    // The capture session that provides video frames.
    private var session: AVCaptureSession?
    private var processBlock:ProcessBlock? = nil
    
    
    // The Metal pipeline. Used for setup in the MTKView
    private var metalDevice: MTLDevice!
    private var metalCommandQueue: MTLCommandQueue!
    private weak var cameraView: MTKView!
    
    // The Core Image pipeline. Used for Updating MTKView
    private var ciContext: CIContext!
    private var currentCIImage: CIImage? {
        didSet {
            cameraView.draw()
        }
    }
    
    var ciOrientation = 5 // default for portrait 
    
    private var scaling:CGPoint = CGPoint(x:1.0,y:1.0)
    func getViewScaling()->CGPoint{
        return scaling
    }
    
    // read only properties
    private var _isRunning:Bool = false
    /// Returns if video processing is active.
    var isRunning:Bool {
        get {
            return self._isRunning
        }
    }
    
    //MARK: Public set and getters
    // for setting the filters pipeline (or whatever processing you are doing)
    /// Set this block to accept and return CIImages. The input to the block is unmodified images from the camera. The output will be rendered to the MTKView.
    func setProcessingBlock(newProcessBlock: @escaping ProcessBlock)
    {
        self.processBlock = newProcessBlock
    }
    

    
    /// Get the Core Image context for where images are rendered. This is typically the same as the MetalDevice (GPU accelerated).
    func getCIContext()->(CIContext?){
        if let context = self.ciContext{
            return context;
        }
        return nil;
    }
    
    
    //MARK: Starting and Stopping functions
    
    /// VisionAnagesic class requires that a MetalView (import MetalKit) is used and passed into the initializer. Class will keep a weak reference to this view. All rendered video will go to this view.
    init(view:MTKView){
        // When running for the first time, just set this to front
        devicePosition = AVCaptureDevice.Position.front
        
        super.init()
        
        // keep a weak reference to the view
        cameraView = view
        
        // setup pipeline for rendering and ciContext
        setupMetal()
        setupCoreImage()
        
        // fire up the video
        start()
        
        // change view transform on orientation change
        NotificationCenter.default.addObserver(self, selector: #selector(self.onOrientationChange), name: UIDevice.orientationDidChangeNotification, object: nil)
        
    }
    
    /// Start the video session and begin processing camera data.
    func start(){
        
        setupCaptureSession()
        self._isRunning = true
    }
    
    /// Stop processing camera data, if running.
    func stop(){
        if (self.session==nil || self.session!.isRunning==false){
            return
        }
        
        self.session!.stopRunning()
        
        self.session = nil
        self.videoDevice = nil
        self._isRunning = false
        
    }
    
    /// Release process block and stop running.
    func shutdown(){
        self.processBlock = nil
        self.stop()
    }
    
    /// Stop the video session and restart with given position and presets. 
    func reset(){
        if(self.isRunning){
            self.stop()
            self.start()
        }
    }
    
    private func setupMetal() {
        metalDevice = MTLCreateSystemDefaultDevice()
        metalCommandQueue = metalDevice.makeCommandQueue()
        
        cameraView.device = metalDevice
        cameraView.isPaused = true
        cameraView.enableSetNeedsDisplay = false
        cameraView.delegate = self
        cameraView.framebufferOnly = false
    }
    
    private func setupCoreImage() {
        ciContext = CIContext(mtlDevice: metalDevice)
    }
    
    // This is the main setup for the video class.
    private func setupCaptureSession() {
        
        // called after start
        // find all devices and see if one is good for desired position
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
        
        
        guard let input = try? AVCaptureDeviceInput(device: self.videoDevice!) else {
            fatalError("Error getting AVCaptureDeviceInput")
        }
        
        if (self.videoDevice?.supportsSessionPreset(AVCaptureSession.Preset(rawValue: self.preset!))==false)
        {
            print("Capture session preset not supported by video device: \(String(describing: self.preset))");
            return;
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            self.session = AVCaptureSession()
            self.session?.sessionPreset = AVCaptureSession.Preset(rawValue: self.preset!)
            self.session?.addInput(input)
            
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            // output updates the UI and MUST be on Main queue
            output.setSampleBufferDelegate(self, queue: .main)
            
            self.session?.addOutput(output)
            output.connections.first?.videoOrientation = .portrait
            self.session?.startRunning()
        }
    }
 
    //MARK: Delegations functions (Internal)
    internal func draw(in view: MTKView) {
        // grab command buffer so we can encode instructions to GPU
        guard let commandBuffer = metalCommandQueue.makeCommandBuffer() else {
            return
        }

        // grab image
        guard let ciImage = currentCIImage else {
            return
        }

        // ensure drawable is free and not tied in the preivous drawing cycle
        guard let currentDrawable = view.currentDrawable else {
            return
        }
        
        // make sure the image is full screen
        let drawSize = cameraView.drawableSize
        let scaleX = drawSize.width / ciImage.extent.width
        let scaleY = drawSize.height / ciImage.extent.height
        
        // update scaling for users wanting to use gestures in view
        scaling = CGPoint(x:2*scaleX,y:2*scaleY)
        
        let newImage = ciImage.transformed(by: .init(scaleX: scaleX, y: scaleY))
        //render into the metal texture
        self.ciContext.render(newImage,
                              to: currentDrawable.texture,
                              commandBuffer: commandBuffer,
                              bounds: newImage.extent,
                              colorSpace: CGColorSpaceCreateDeviceRGB())

        // register drawwable to command buffer
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
    
    internal func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Delegate method not implemented.
    }
    
    internal func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Grab the pixelbuffer frame from the camera output
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        processVideoFrame(pixelBuffer)
    }
    
    private func processVideoFrame(_ framePixelBuffer: CVPixelBuffer) {
        
        //NOTE for the future :
        // This is where we could use the sample buffer to initiate a request to the Vision Framework
        // Will need to setup a way to start and handle requests
            
        let sourceImage = CIImage(cvPixelBuffer: framePixelBuffer, options:nil)
        
        // run through a filter
        var filteredImage:CIImage! = sourceImage;
        
        if(self.processBlock != nil){
            filteredImage=self.processBlock!(sourceImage)
        }
        
        currentCIImage = filteredImage
        
        
    }
    
    //MARK: Notifications Subscribe and Remove
    @objc
    func onOrientationChange(){
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // adjust phone to new orientation
            // just pass for now
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        print("\(Self.self) object was deallocated")
    }

    
    
}


//MARK: Flash and FPS Methods
extension VisionAnalgesic {
    
    /// Toggle the flash for the phone on or off. This function is only available when using the back position camera and will fail if attempted when the phone is using the front cameras. The flash can also cause the phone to overheat, which will result in a failure of the flash to turn on. Returns: true if the flash is overheated, false if the flash is stable.
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
    
    
    /// Turn the flash for the phone to a specific level between 0.0 and 1.0. This function is only available when using the back position camera and will fail if attempted when the phone is using the front cameras. The flash can also cause the phone to overheat, which will result in a failure of the flash to turn on. Returns: true if the flash is overheated, false if the flash is stable.
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
    
    /// Turn the flash for the phone off. This function is only available when using the back position camera and will fail if attempted when the phone is using the front cameras.
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
    
    
    // for setting the camera we should use
    func setCameraPosition(position: AVCaptureDevice.Position){
        // AVCaptureDevicePosition.Back
        // AVCaptureDevicePosition.Front
        if(position != self.devicePosition){
            self.devicePosition = position;
            self.reset()
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
        
        self.reset()
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
            self.reset()
        }
    }
    
}

//MARK: Utility for Getting Orientation
extension VisionAnalgesic {
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
}
