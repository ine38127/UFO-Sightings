//
//  ShapeSelectorViewController.h
//  UfoSightings
//
//  Created by Richard Kirk on 5/16/12.
//  Copyright (c) 2012 Home. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "UFOFilterViewController.h"
#import "UFOBaseViewController.h"

@interface ShapeSelectorViewController : UFOBaseViewController <UIScrollViewDelegate, UFOPredicateCreation>

@property (strong, nonatomic) NSArray* shipShapes;
@property (weak, nonatomic) IBOutlet UIScrollView *scrollView;


@end
