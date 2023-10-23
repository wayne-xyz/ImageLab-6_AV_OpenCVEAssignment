//
//  OpenCVBridge.m
//  LookinLive
//
//  Created by Eric Larson.
//  Copyright (c) Eric Larson. All rights reserved.
//

#import "OpenCVBridge.hh"


using namespace cv;

@interface OpenCVBridge()
@property (nonatomic) cv::Mat image;
@property (strong,nonatomic) CIImage* frameInput;
@property (nonatomic) CGRect bounds;
@property (nonatomic) CGAffineTransform transform;
@property (nonatomic) CGAffineTransform inverseTransform;
@property (atomic) cv::CascadeClassifier classifier;
@end

@implementation OpenCVBridge



#pragma mark ===Write Your Code Here===
// you can define your own functions here for processing the image


#pragma mark Define Custom Functions Here
-(void)processImage{
    
    cv::Mat frame_gray,image_copy;
    const int kCannyLowThreshold = 150;
    const int kFilterKernelSize = 5;
    
    
    
    
    switch (self.processType) {
        case 1:
        {
            // get rid of alpha channel
            cvtColor(_image, image_copy, CV_BGRA2BGR);
            // make gray
            cvtColor( image_copy, frame_gray, CV_BGR2GRAY );
            // take the inverse of gray image
            bitwise_not(frame_gray, _image);
            // convert back to RGB for display.
            cvtColor( _image, _image, CV_GRAY2BGRA );
            return;
            break;
        }
        case 2:
        {
            static uint counter = 0;
            cvtColor(_image, image_copy, CV_BGRA2BGR);
            for(int i=0;i<counter;i++){
                for(int j=0;j<counter;j++){
                    uchar *pt = image_copy.ptr(i, j);
                    pt[0] = 255;
                    pt[1] = 0;
                    pt[2] = 255;
                    
                    pt[3] = 255;
                    pt[4] = 0;
                    pt[5] = 0;
                }
            }
            cvtColor(image_copy, _image, CV_BGR2BGRA);
            
            counter++;
            counter = counter>50 ? 0 : counter;
            break;
        }
        case 3:
        { // fine, adding scoping to case statements to get rid of jump errors
            // FOR FLIPPED ASSIGNMENT, YOU MAY BE INTERESTED IN THIS EXAMPLE
            char text[50];
            Scalar avgPixelIntensity;
            
            cvtColor(_image, image_copy, CV_BGRA2BGR); // get rid of alpha for processing
            avgPixelIntensity = cv::mean( image_copy );
            // they say that sprintf is depricated, but it still works for c++
            sprintf(text,"Avg. B: %.0f, G: %.0f, R: %.0f", avgPixelIntensity.val[0],avgPixelIntensity.val[1],avgPixelIntensity.val[2]);
            cv::putText(_image, text, cv::Point(0, 20), FONT_HERSHEY_PLAIN, 2.0, Scalar::all(255), 1, 2);
            break;
        }
        case 4:
        {
            vector<Mat> layers;
            cvtColor(_image, image_copy, CV_BGRA2BGR);
            cvtColor(image_copy, image_copy, CV_BGR2HSV);
            
            //grab  just the Hue chanel
            cv::split(image_copy,layers);
            
            // shift the colors
            cv::add(layers[0],80.0,layers[0]);
            
            // get back image from separated layers
            cv::merge(layers,image_copy);
            
            cvtColor(image_copy, image_copy, CV_HSV2BGR);
            cvtColor(image_copy, _image, CV_BGR2BGRA);
            break;
        }
        case 5:
        {
            //============================================
            //threshold the image using the utsu method (optimal histogram point)
            cvtColor(_image, image_copy, COLOR_BGRA2GRAY);
            cv::threshold(image_copy, image_copy, 0, 255, CV_THRESH_BINARY | CV_THRESH_OTSU);
            cvtColor(image_copy, _image, CV_GRAY2BGRA); //add back for display
            break;
        }
        case 6:
        {
            //============================================
            //do some blurring (filtering)
            cvtColor(_image, image_copy, CV_BGRA2BGR);
            Mat gauss = cv::getGaussianKernel(11, 9);
            cv::filter2D(image_copy, image_copy, -1, gauss);
            cvtColor(image_copy, _image, CV_BGR2BGRA);
            break;
        }
        case 7:
        {
            //============================================
            // canny edge detector
            // Convert captured frame to grayscale
            cvtColor(_image, image_copy, COLOR_BGRA2GRAY);
            
            // Perform Canny edge detection
            Canny(image_copy, _image,
                  kCannyLowThreshold,
                  kCannyLowThreshold*7,
                  kFilterKernelSize);
            
            // copy back for further processing
            cvtColor(_image, _image, CV_GRAY2BGRA); //add back for display
            break;
        }
        case 8:
        {
            //============================================
            // contour detector with rectangle bounding
            // Convert captured frame to grayscale
            vector<vector<cv::Point> > contours; // for saving the contours
            vector<cv::Vec4i> hierarchy;
            
            cvtColor(_image, frame_gray, CV_BGRA2GRAY);
            
            // Perform Canny edge detection
            Canny(frame_gray, image_copy,
                  kCannyLowThreshold,
                  kCannyLowThreshold*7,
                  kFilterKernelSize);
            
            // convert edges into connected components
            findContours( image_copy, contours, hierarchy, CV_RETR_CCOMP, CV_CHAIN_APPROX_SIMPLE, cv::Point(0, 0) );
            
            // draw boxes around contours in the original image
            for( int i = 0; i< contours.size(); i++ )
            {
                cv::Rect boundingRect = cv::boundingRect(contours[i]);
                cv::rectangle(_image, boundingRect, Scalar(255,255,255,255));
            }
            break;
            
        }
        case 9:
        {
            //============================================
            // contour detector with full bounds drawing
            // Convert captured frame to grayscale
            vector<vector<cv::Point> > contours; // for saving the contours
            vector<cv::Vec4i> hierarchy;
            
            cvtColor(_image, frame_gray, CV_BGRA2GRAY);
            
            
            // Perform Canny edge detection
            Canny(frame_gray, image_copy,
                  kCannyLowThreshold,
                  kCannyLowThreshold*7,
                  kFilterKernelSize);
            
            // convert edges into connected components
            findContours( image_copy, contours, hierarchy,
                         CV_RETR_CCOMP,
                         CV_CHAIN_APPROX_SIMPLE,
                         cv::Point(0, 0) );
            
            // draw the contours to the original image
            for( int i = 0; i< contours.size(); i++ )
            {
                Scalar color = Scalar( rand()%255, rand()%255, rand()%255, 255 );
                drawContours( _image, contours, i, color, 1, 4, hierarchy, 0, cv::Point() );
                
            }
            break;
        }
        case 10:
        {
            // Convert it to gray
            cvtColor( _image, image_copy, CV_BGRA2GRAY );
            
            // Reduce the noise
            GaussianBlur( image_copy, image_copy, cv::Size(3, 3), 2, 2 );
            
            vector<Vec3f> circles;
            
            // Apply the Hough Transform to find the circles
            HoughCircles( image_copy, circles,
                         CV_HOUGH_GRADIENT,
                         1, // downsample factor
                         image_copy.rows/20, // distance between centers
                         kCannyLowThreshold, // canny upper thresh
                         40, // magnitude thresh for hough param space
                         0, 0 ); // min/max centers
            
            // Draw the circles detected
            for( size_t i = 0; i < circles.size(); i++ )
            {
                cv::Point center(cvRound(circles[i][0]), cvRound(circles[i][1]));
                int radius = cvRound(circles[i][2]);
                // circle center
                circle( _image, center, 3, Scalar(0,255,0,255), -1, 8, 0 );
                // circle outline
                circle( _image, center, radius, Scalar(0,0,255,255), 3, 8, 0 );
            }
            break;
        }
        case 11:
        {
            // example for running Haar cascades
            //============================================
            // generic Haar Cascade
            
            cvtColor(_image, image_copy, CV_BGRA2GRAY);
            vector<cv::Rect> objects;
            
            // run classifier
            // error if this is not set!
            self.classifier.detectMultiScale(image_copy, objects);
            
            // display bounding rectangles around the detected objects
            for( vector<cv::Rect>::const_iterator r = objects.begin(); r != objects.end(); r++)
            {
                cv::rectangle( _image, cvPoint( r->x, r->y ), cvPoint( r->x + r->width, r->y + r->height ), Scalar(0,0,255,255));
                
            }
            //image already in the correct color space
            break;
        }
            
        default:
            break;
            
    }
}


#pragma mark ====Do Not Manipulate Code below this line!====
-(void)setTransforms:(CGAffineTransform)trans{
    self.inverseTransform = trans;
    self.transform = CGAffineTransformInvert(trans);
}

-(void)loadHaarCascadeWithFilename:(NSString*)filename{
    NSString *filePath = [[NSBundle mainBundle] pathForResource:filename ofType:@"xml"];
    self.classifier = cv::CascadeClassifier([filePath UTF8String]);
}

-(instancetype)init{
    self = [super init];
    
    if(self != nil){
        //self.transform = CGAffineTransformMakeRotation(M_PI_2);
        //self.transform = CGAffineTransformScale(self.transform, -1.0, 1.0);
        
        //self.inverseTransform = CGAffineTransformMakeScale(-1.0,1.0);
        //self.inverseTransform = CGAffineTransformRotate(self.inverseTransform, -M_PI_2);
        self.transform = CGAffineTransformIdentity;
        self.inverseTransform = CGAffineTransformIdentity;
        
    }
    return self;
}

#pragma mark Bridging OpenCV/CI Functions
// code manipulated from
// http://stackoverflow.com/questions/30867351/best-way-to-create-a-mat-from-a-ciimage
// http://stackoverflow.com/questions/10254141/how-to-convert-from-cvmat-to-uiimage-in-objective-c


-(void) setImage:(CIImage*)ciFrameImage
      withBounds:(CGRect)faceRectIn
      andContext:(CIContext*)context{
    
    CGRect faceRect = CGRect(faceRectIn);
    faceRect = CGRectApplyAffineTransform(faceRect, self.transform);
    ciFrameImage = [ciFrameImage imageByApplyingTransform:self.transform];
    
    
    //get face bounds and copy over smaller face image as CIImage
    //CGRect faceRect = faceFeature.bounds;
    _frameInput = ciFrameImage; // save this for later
    _bounds = faceRect;
    CIImage *faceImage = [ciFrameImage imageByCroppingToRect:faceRect];
    CGImageRef faceImageCG = [context createCGImage:faceImage fromRect:faceRect];
    
    // setup the OPenCV mat fro copying into
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(faceImageCG);
    CGFloat cols = faceRect.size.width;
    CGFloat rows = faceRect.size.height;
    cv::Mat cvMat(rows, cols, CV_8UC4); // 8 bits per component, 4 channels
    _image = cvMat;
    
    // setup the copy buffer (to copy from the GPU)
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                // Pointer to backing data
                                                    cols,                      // Width of bitmap
                                                    rows,                      // Height of bitmap
                                                    8,                         // Bits per component
                                                    cvMat.step[0],             // Bytes per row
                                                    colorSpace,                // Colorspace
                                                    kCGImageAlphaNoneSkipLast |
                                                    //kCGImageAlphaLast |
                                                    kCGBitmapByteOrderDefault); // Bitmap info flags
    // do the copy
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), faceImageCG);
    
    // release intermediary buffer objects
    CGContextRelease(contextRef);
    CGImageRelease(faceImageCG);
    
}

-(CIImage*)getImage{
    
    // convert back
    // setup NS byte buffer using the data from the cvMat to show
    NSData *data = [NSData dataWithBytes:_image.data
                                  length:_image.elemSize() * _image.total()];
    
    CGColorSpaceRef colorSpace;
    if (_image.elemSize() == 1) {
        colorSpace = CGColorSpaceCreateDeviceGray();
    } else {
        colorSpace = CGColorSpaceCreateDeviceRGB();
    }
    
    // setup buffering object
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    
    // setup the copy to go from CPU to GPU
    CGImageRef imageRef = CGImageCreate(_image.cols,                                     // Width
                                        _image.rows,                                     // Height
                                        8,                                              // Bits per component
                                        8 * _image.elemSize(),                           // Bits per pixel
                                        _image.step[0],                                  // Bytes per row
                                        colorSpace,                                     // Colorspace
                                        //kCGImageAlphaLast |
                                        kCGBitmapByteOrderDefault,  // Bitmap info flags
                                        provider,                                       // CGDataProviderRef
                                        NULL,                                           // Decode
                                        false,                                          // Should interpolate
                                        kCGRenderingIntentDefault);                     // Intent
    
    // do the copy inside of the object instantiation for retImage
    CIImage* retImage = [[CIImage alloc]initWithCGImage:imageRef];
    CGAffineTransform transform = CGAffineTransformMakeTranslation(self.bounds.origin.x, self.bounds.origin.y);
    retImage = [retImage imageByApplyingTransform:transform];
    retImage = [retImage imageByApplyingTransform:self.inverseTransform];
    
    // clean up
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
    return retImage;
}

-(CIImage*)getImageComposite{
    
    // convert back
    // setup NS byte buffer using the data from the cvMat to show
    NSData *data = [NSData dataWithBytes:_image.data
                                  length:_image.elemSize() * _image.total()];
    
    CGColorSpaceRef colorSpace;
    if (_image.elemSize() == 1) {
        colorSpace = CGColorSpaceCreateDeviceGray();
    } else {
        colorSpace = CGColorSpaceCreateDeviceRGB();
    }
    
    // setup buffering object
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    
    // setup the copy to go from CPU to GPU
    CGImageRef imageRef = CGImageCreate(_image.cols,                                     // Width
                                        _image.rows,                                     // Height
                                        8,                                              // Bits per component
                                        8 * _image.elemSize(),                           // Bits per pixel
                                        _image.step[0],                                  // Bytes per row
                                        colorSpace,                                     // Colorspace
                                        kCGImageAlphaNoneSkipLast,
                                        //kCGImageAlphaLast |
                                        //kCGBitmapByteOrderDefault,  // Bitmap info flags
                                        provider,                                       // CGDataProviderRef
                                        NULL,                                           // Decode
                                        false,                                          // Should interpolate
                                        kCGRenderingIntentDefault);                     // Intent
    
    // do the copy inside of the object instantiation for retImage
    CIImage* retImage = [[CIImage alloc]initWithCGImage:imageRef];
    // now apply transforms to get what the original image would be inside the Core Image frame
    CGAffineTransform transform = CGAffineTransformMakeTranslation(self.bounds.origin.x, self.bounds.origin.y);
    retImage = [retImage imageByApplyingTransform:transform];
    CIFilter* filt = [CIFilter filterWithName:@"CISourceAtopCompositing"
                          withInputParameters:@{@"inputImage":retImage,@"inputBackgroundImage":self.frameInput}];
    retImage = filt.outputImage;
    
    // clean up
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
    retImage = [retImage imageByApplyingTransform:self.inverseTransform];
    
    return retImage;
}




@end
