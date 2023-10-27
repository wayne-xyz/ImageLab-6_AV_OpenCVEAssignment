//
//  ViewController.swift
//  ImageLab
//
//  Created by Eric Larson
//  Copyright © Eric Larson. All rights reserved.
//
// Two question.
//1.100points collection, beacuse the camera FPS is 60. so every second we can get 60 points of three color chanel. When we can get the 100points, we may collect 1.66seconds about 1666 milliseconds.
//2. The OpenCVBridege as model can directly control the UI to add image in the MainView. So it dose not adhere the paradigm of Model view Controller.

import UIKit
import AVFoundation
import MetalKit

class ViewController: UIViewController   {

    //MARK: Class Properties
    var filters : [CIFilter]! = nil
    var videoManager:VisionAnalgesic! = nil
    let pinchFilterIndex = 2
    var detector:CIDetector! = nil
    let bridge = OpenCVBridge()
    var fingerFlashFlag=false; // for check the flash is from finger
    
    //MARK: Outlets in view
    @IBOutlet weak var flashSlider: UISlider!
    @IBOutlet weak var stageLabel: UILabel!
    @IBOutlet weak var cameraView: MTKView!
    
    //MARK: Two toggle button in view can be disable in part3
    
    @IBOutlet weak var flashButton: UIButton!
    @IBOutlet weak var cameraButton: UIButton!
    
    
    //MARK: ViewController Hierarchy
    override func viewDidLoad() {
        super.viewDidLoad()
            
        self.view.backgroundColor = nil
        
        // setup the OpenCV bridge nose detector, from file
        self.bridge.loadHaarCascade(withFilename: "nose")
        
        self.videoManager = VisionAnalgesic(view: self.cameraView)
        
        // MARK: Part one  set back camera
        // use the back camera
        self.videoManager.setCameraPosition(position: AVCaptureDevice.Position.back)// sometimes bug here, sometime back camera, somtime front one
        
        
        // not for finger function below comments
        // create dictionary for face detection
        // HINT: you need to manipulate these properties for better face detection efficiency
//        let optsDetector = [CIDetectorAccuracy:CIDetectorAccuracyHigh,
//                      CIDetectorNumberOfAngles:11,
//                      CIDetectorTracking:false] as [String : Any]
        
        // setup a face detector in swift
//        self.detector = CIDetector(ofType: CIDetectorTypeFace,
//                                  context: self.videoManager.getCIContext(), // perform on the GPU is possible
//            options: (optsDetector as [String : AnyObject]))
        
        // MARK: Part One call the processFinger function
        self.videoManager.setProcessingBlock(newProcessBlock: self.processFinger)// call the process Finger rather than ProcessImageSwift
        
        if !videoManager.isRunning{
            videoManager.start()        }
        
    
    }
    
    // MARK: Part one set processFinger
    func processFinger(inputImage:CIImage) -> CIImage{
        var returnImage=inputImage
        self.bridge.setImage(returnImage, withBounds: returnImage.extent, andContext: self.videoManager.getCIContext())
        let processFingerResult=self.bridge.processFinger()
        returnImage=self.bridge.getImage()
        fingerCoverDectect(coveringBoolFlag: processFingerResult)
        return returnImage
    }
    
    // MARK: PART 3
    // update the ui one label to show what status for the covering
    // update the toggle buttons
    func fingerCoverDectect(coveringBoolFlag:Bool){
        if coveringBoolFlag==true{  // when something is covering disable the two button
            self.flashButton.isEnabled=false
            self.cameraButton.isEnabled=false
          //  self.flashSlider.isEnabled=false
        }else{
            self.flashButton.isEnabled=true
            self.cameraButton.isEnabled=true
         //   self.flashSlider.isEnabled=true
        }
        
        // finger cover happen, turn on/off flash, avoid running everytime.
        if self.bridge.coverStatus==1{
            if(self.fingerFlashFlag==false){
                self.videoManager.turnOnFlashwithLevel(1.0)
                self.fingerFlashFlag=true;
                print("flash on.")
            }
            stageLabel.text="☝️ Finger is covering your camera 📱📸 "
        }else if self.bridge.coverStatus==2{
            stageLabel.text=" Somthing is covering your camera 📱📸"
        }else{
            if self.fingerFlashFlag{
                self.videoManager.turnOffFlash()
                self.fingerFlashFlag=false;
            }
            stageLabel.text=""
        }
        
    }
    
    
    // remove this func when i detect the finger
    //MARK: Process image output
    func processImageSwift(inputImage:CIImage) -> CIImage{
        
        // detect faces
        let f = getFaces(img: inputImage)
        
        // if no faces, just return original image
        if f.count == 0 { return inputImage }
        
        var retImage = inputImage
        
        //-------------------Example 1----------------------------------
        // if you just want to process on separate queue use this code
        // this is a NON BLOCKING CALL, but any changes to the image in OpenCV cannot be displayed real time
        /*
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)) { () -> Void in
            self.bridge.setImage(retImage, withBounds: retImage.extent, andContext: self.videoManager.getCIContext())
            self.bridge.processImage()
        }
         */
        
        //-------------------Example 2----------------------------------
        // use this code if you are using OpenCV and want to overwrite the displayed image via OpenCV
        // this is a BLOCKING CALL
        /*
        // FOR FLIPPED ASSIGNMENT, YOU MAY BE INTERESTED IN THIS EXAMPLE
        
        self.bridge.setImage(retImage, withBounds: retImage.extent, andContext: self.videoManager.getCIContext())
        self.bridge.processImage()
        retImage = self.bridge.getImage()
         */
        
        //-------------------Example 3----------------------------------
        //You can also send in the bounds of the face to ONLY process the face in OpenCV
        // or any bounds to only process a certain bounding region in OpenCV
        
        self.bridge.setImage(retImage,
                             withBounds: f[0].bounds, // the first face bounds
                             andContext: self.videoManager.getCIContext())
        
        self.bridge.processImage()
        retImage = self.bridge.getImageComposite() // get back opencv processed part of the image (overlayed on original)
        
        return retImage
    }
    
    //MARK: Setup Face Detection
    
    func getFaces(img:CIImage) -> [CIFaceFeature]{
        // this ungodly mess makes sure the image is the correct orientation
        let optsFace = [CIDetectorImageOrientation:self.videoManager.ciOrientation]
        // get Face Features
        return self.detector.features(in: img, options: optsFace) as! [CIFaceFeature]
        
    }
    
    
    // change the type of processing done in OpenCV
    @IBAction func swipeRecognized(_ sender: UISwipeGestureRecognizer) {
       // cancel this function for the assignment
//        switch sender.direction {
//        case .left:
//            if self.bridge.processType <= 10 {
//                self.bridge.processType += 1
//            }
//        case .right:
//            if self.bridge.processType >= 1{
//                self.bridge.processType -= 1
//            }
//        default:
//            break
//            
//        }
//        
//        stageLabel.text = "Stage: \(self.bridge.processType)"

    }
    
    //MARK: Convenience Methods for UI Flash and Camera Toggle
    @IBAction func flash(_ sender: AnyObject) {
        if(self.videoManager.toggleFlash()){
            self.flashSlider.value = 1.0
        }
        else{
            self.flashSlider.value = 0.0
        }
    }
    
    @IBAction func switchCamera(_ sender: AnyObject) {
        self.videoManager.toggleCameraPosition()
    }
    
    @IBAction func setFlashLevel(_ sender: UISlider) {
        if(sender.value>0.0){
            let val = self.videoManager.turnOnFlashwithLevel(sender.value)
            if val {
                print("Flash return, no errors.")
            }
        }
        else if(sender.value==0.0){
            self.videoManager.turnOffFlash()
        }
    }

   
}

