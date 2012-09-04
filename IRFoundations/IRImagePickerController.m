//
//  IRCameraViewController.m
//  IRFoundations
//
//  Created by Evadne Wu on 6/8/11.
//  Copyright 2011 Iridia Productions. All rights reserved.
//

#import <AudioToolbox/AudioToolbox.h>
#import "UIImage+IRAdditions.h"
#import "IRImagePickerController.h"
#import <AssetsLibrary/AssetsLibrary.h>


static NSString * const kIRImagePickerControllerVolumeDidChangeNotification = @"IRImagePickerControllerVolumeDidChangeNotification";

void IRImagePickerController_handleAudioVolumeChange (void *userData, AudioSessionPropertyID propertyID, UInt32 dataSize, const void *data) {

	[[NSNotificationCenter defaultCenter] postNotificationName:kIRImagePickerControllerVolumeDidChangeNotification object:nil];
	
	AudioSessionSetProperty(propertyID, dataSize, data);

}

static NSString * const kIRImagePickerControllerAssetLibrary = @"IRImagePickerControllerAssetLibrary";

@interface IRImagePickerController () <UINavigationControllerDelegate, UIImagePickerControllerDelegate>

@property (nonatomic, readwrite, copy) IRImagePickerCallback callbackBlock;
@property (nonatomic, readwrite, strong) ALAssetsLibrary *assetsLibrary;

@end


@implementation IRImagePickerController

@synthesize callbackBlock, takesPictureOnVolumeUpKeypress;
@synthesize onViewWillAppear, onViewDidAppear, onViewWillDisappear, onViewDidDisappear;
@synthesize asynchronous;
@synthesize assetsLibrary;

+ (IRImagePickerController *) savedImagePickerWithCompletionBlock:(IRImagePickerCallback)aCallbackBlockOrNil {
    
	return [self pickerWithAssetsLibrary:nil SourceType:UIImagePickerControllerSourceTypeSavedPhotosAlbum mediaTypes:[NSArray arrayWithObject:(id)kUTTypeImage] completionBlock:aCallbackBlockOrNil];
    
}

+ (IRImagePickerController *) photoLibraryPickerWithCompletionBlock:(IRImagePickerCallback)aCallbackBlockOrNil {
	
	return [self pickerWithAssetsLibrary:nil SourceType:UIImagePickerControllerSourceTypePhotoLibrary mediaTypes:[NSArray arrayWithObject:(id)kUTTypeImage] completionBlock:aCallbackBlockOrNil];
    
}

+ (IRImagePickerController *) cameraCapturePickerWithCompletionBlock:(IRImagePickerCallback)aCallbackBlockOrNil {
    
	return [self pickerWithAssetsLibrary:nil SourceType:UIImagePickerControllerSourceTypeCamera mediaTypes:[NSArray arrayWithObjects:(id)kUTTypeImage, (id)kUTTypeMovie, nil] completionBlock:aCallbackBlockOrNil];
    
}

+ (IRImagePickerController *) cameraImageCapturePickerWithAssetsLibrary:(ALAssetsLibrary *)assetsLibrary completionBlock:(IRImagePickerCallback)aCallbackBlockOrNil {
    
	return [self pickerWithAssetsLibrary:assetsLibrary SourceType:UIImagePickerControllerSourceTypeCamera mediaTypes:[NSArray arrayWithObject:(id)kUTTypeImage] completionBlock:aCallbackBlockOrNil];
    
}

+ (IRImagePickerController *) cameraVideoCapturePickerWithCompletionBlock:(IRImagePickerCallback)aCallbackBlockOrNil {
    
	return [self pickerWithAssetsLibrary:nil SourceType:UIImagePickerControllerSourceTypeCamera mediaTypes:[NSArray arrayWithObject:(id)kUTTypeMovie] completionBlock:aCallbackBlockOrNil];
    
}

+ (IRImagePickerController *) pickerWithAssetsLibrary:(ALAssetsLibrary *)assetsLibrary SourceType:(UIImagePickerControllerSourceType)aSourceType mediaTypes:(NSArray *)inMediaTypes completionBlock:(IRImagePickerCallback)aCallbackBlockOrNil {
	
	if (![[self class] isSourceTypeAvailable:aSourceType])
		return nil;
	
	IRImagePickerController *returned = [[self alloc] init];
	if (!returned)
		return nil;
	
	returned.takesPictureOnVolumeUpKeypress = YES;
	returned.sourceType = aSourceType;
	returned.mediaTypes = inMediaTypes;
	returned.callbackBlock = aCallbackBlockOrNil;
	returned.delegate = returned;
  returned.assetsLibrary = assetsLibrary;
	
	return returned;
    
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {

	return YES;

}

- (void) imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    
	UIImage *assetImage = [info valueForKey:UIImagePickerControllerOriginalImage];
	UIImage *editedImage = [info valueForKey:UIImagePickerControllerEditedImage];
  NSDictionary *metadata = [info valueForKey:UIImagePickerControllerMediaMetadata];
	
	if (editedImage)
		assetImage = editedImage;
	
	if (self.sourceType == UIImagePickerControllerSourceTypeCamera) {

    __weak IRImagePickerController *wSelf = self;
    [self.assetsLibrary writeImageToSavedPhotosAlbum:[assetImage CGImage] metadata:metadata completionBlock:^(NSURL *assetURL, NSError *error) {

      [wSelf.assetsLibrary assetForURL:assetURL resultBlock:^(ALAsset *asset) {

        wSelf.callbackBlock(asset);

      } failureBlock:^(NSError *error) {

        NSLog(@"Unable to read asset:%@ from camera roll, error:%@", assetURL, error);
        wSelf.callbackBlock(nil);

      }];

    }];
		
	} else {

    NSAssert(NO, @"Unsupported source type of image picker controller");

  }
    
}

- (void) imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    
	if (self.callbackBlock)
		self.callbackBlock(nil);
    
}





- (void) viewWillAppear:(BOOL)animated {

	[super viewWillAppear:animated];
		
	if (self.onViewWillAppear)
		self.onViewWillAppear(animated);

	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		
		AudioSessionAddPropertyListener(kAudioSessionProperty_CurrentHardwareOutputVolume, IRImagePickerController_handleAudioVolumeChange, NULL);
	});

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleVolumeChanged:) name:kIRImagePickerControllerVolumeDidChangeNotification object:nil];
	
}

- (void) viewDidAppear:(BOOL)animated {

	if (self.onViewDidAppear)
		self.onViewDidAppear(animated);
	
	[super viewDidAppear:animated];

}

- (void) viewWillDisappear:(BOOL)animated {

	[super viewWillDisappear:animated];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self name:kIRImagePickerControllerVolumeDidChangeNotification object:nil];
	
	if (self.onViewWillDisappear)
		self.onViewWillDisappear(animated);

}

- (void) viewDidDisappear:(BOOL)animated {

	if (self.onViewDidDisappear)
		self.onViewDidDisappear(animated);

	[super viewDidDisappear:animated];

}

- (void) handleVolumeChanged:(NSNotification *)aNotification {

	if (self.sourceType == UIImagePickerControllerSourceTypeCamera) {
	
		if (self.takesPictureOnVolumeUpKeypress)
		if ([self sourceType] == UIImagePickerControllerSourceTypeCamera)
			[self takePicture];
			
	}

}

@end
