//
//  RootViewController.m
//  UfoSightings
//
//  Created by Richard Kirk on 5/23/12.
//  Copyright (c) 2012 Home. All rights reserved.
//

#import "UFORootController.h"
#import <CoreData/CoreData.h>

@interface UFORootController ()
{
    UIViewController* _currentViewController;
}
@end

@implementation UFORootController


- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin| UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;

    self.view.backgroundColor = [UIColor blackColor];
    _currentViewController = self.mapViewController;
    [self.view addSubview:_currentViewController.view];
}


- (UFOMapViewController*)mapViewController
{
    if(!_mapViewController) {
        _mapViewController = [[UFOMapViewController alloc]init];
        _mapViewController.delegate = self;
        _mapViewController.view.frame = self.view.bounds;
    }
    return _mapViewController;
}


- (UFODatabaseExplorerViewController*)databaseViewController
{
    if(!_databaseViewController) {
        _databaseViewController = [[UFODatabaseExplorerViewController alloc]init];
        _databaseViewController.delegate = self;
        _databaseViewController.view.frame = self.view.bounds;
    }
    return _databaseViewController;
}


- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
	return YES;
}


- (void)switchViewController
{
    UIDeviceOrientation deviceOrientation = [[UIApplication sharedApplication]statusBarOrientation];
    UIViewController* nextViewController;
    UIViewAnimationOptions animationOption;
    if([_currentViewController isKindOfClass:[UFODatabaseExplorerViewController class]]) {
        animationOption = UIInterfaceOrientationIsLandscape(deviceOrientation) ? UIViewAnimationOptionTransitionFlipFromBottom: UIViewAnimationOptionTransitionFlipFromLeft;
        nextViewController = self.mapViewController;
    }
    else {
        animationOption = UIInterfaceOrientationIsLandscape(deviceOrientation) ? UIViewAnimationOptionTransitionFlipFromTop : UIViewAnimationOptionTransitionFlipFromRight;
        nextViewController = self.databaseViewController;
    }
    
    nextViewController.view.frame = self.view.bounds;
     
     [UIView transitionWithView:self.view duration:1.5f options:animationOption animations:^{
         [self.view addSubview:nextViewController.view];
     } completion:^(BOOL finished){
         [_currentViewController.view removeFromSuperview];
         _currentViewController = nil;
         _currentViewController = nextViewController;
     }];
}


#pragma mark - UFOMapViewController Delegate protocols

- (void)UFOMapViewControllerWantsToExit:(UFOMapViewController *)mapController
{
    [self switchViewController];
}


#pragma mark - UFODatabaseExplorer Delegate protocols

- (void)UFODatabaseExplorerWantsToViewMap:(UFODatabaseExplorerViewController *)databaseExplorer
{
    [self switchViewController];
}

@end
