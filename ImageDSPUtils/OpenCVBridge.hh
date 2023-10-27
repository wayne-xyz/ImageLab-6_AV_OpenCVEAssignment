//
//  OpenCVBridge.h
//  LookinLive
//
//  Created by Eric Larson.
//  Copyright (c) Eric Larson. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import "AVFoundation/AVFoundation.h"

#import "PrefixHeader.pch"

@interface OpenCVBridge : NSObject

@property (nonatomic) NSInteger processType;
@property (nonatomic) NSInteger coverStatus; //0means nocover , 1 finger cover ,2 something other than finger

//MARK: Part 3
// three array tosave the data
@property (nonatomic, strong) NSMutableArray<NSNumber *> *redArray;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *greenArray;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *blueArray;
@property (nonatomic) bool capturedFlag; //default false which means didnt start catch


// set the image for processing later
-(void) setImage:(CIImage*)ciFrameImage
      withBounds:(CGRect)rect
      andContext:(CIContext*)context;

//get the image raw opencv
-(CIImage*)getImage;

//get the image inside the original bounds
-(CIImage*)getImageComposite;

// call this to perfrom processing (user controlled for better transparency)
-(void)processImage;

// MARK: Part one creat a public fucntion
// Part one call this to detect the finger covering the camera
-(bool)processFinger;

// for the video manager transformations
-(void)setTransforms:(CGAffineTransform)trans;

-(void)loadHaarCascadeWithFilename:(NSString*)filename;

@end
