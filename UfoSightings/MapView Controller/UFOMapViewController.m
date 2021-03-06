//
//  UFOMapViewController.m
//  UFO Sightings
//
//  Created by Richard Kirk on 12/19/11.
//  Copyright (c) 2011 Home. All rights reserved.
//

#import "UFOMapViewController.h"
#import "UFORootController.h"
#import "Sighting.h"
#import "UFOHeatMap.h"
#import "MapModalView.h"

#define DEGREES_TO_RADIANS(angle) (angle / 180.0 * M_PI)
#define CLUSTER_ANIMATION YES
#define APPROXIMATE_CENTER_ANNOTATION YES

static dispatch_queue_t annons_background_queue;
dispatch_queue_t annotations_background_queue()
{
    if (annons_background_queue == NULL) {
        annons_background_queue = dispatch_queue_create("com.richardKirk.annotations.backgroundfetches", DISPATCH_QUEUE_SERIAL);
    }
    return annons_background_queue;
}

static dispatch_queue_t title_generation_backgrond_queue;
dispatch_queue_t title_backgrond_queue()
{
    if (title_generation_backgrond_queue == NULL) {
        title_generation_backgrond_queue = dispatch_queue_create("com.richardKirk.titles.backgroundfetches", DISPATCH_QUEUE_SERIAL);
    }
    return title_generation_backgrond_queue;
}


@interface UFOMapViewController()
{
    MKMapView *                 _backMap;
    MapModalView*               _modalView;
    bool                        _mapSelectionOpen;
    __block bool                _isFetching;
    __block bool                _stopGettingTitle;
    MKAnnotationView*           _selectedAnnotationView;
}
@property (strong, nonatomic) UIActivityIndicatorView* annotationActivityIndicator;
@property (assign, nonatomic) BOOL annotationsShowing;
@property (assign, nonatomic) BOOL heatMapShowing;

- (void)updateVisibleAnnotations;
- (id<MKAnnotation>)centerAnnotationInGrid:(MKMapRect)gridMapRect usingAnnotations:(NSSet*)annotations;
- (void)reloadSightingLocations;
- (void)showAlert;
- (void)hideAlert;
@end


@implementation UFOMapViewController

#pragma mark - View lifecycle
- (id)init
{
    if((self = [super init])) {
        _heatMapOverlay = [[UFOHeatMap alloc]init];
        _backMap = [[MKMapView alloc]initWithFrame:CGRectZero];
        _mapSelectionOpen = NO;
        _isFetching = NO;
        _stopGettingTitle = NO;
    }
    return self;
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    MKCoordinateRegion region = {{ 36.102376, -119.091797}, {32.451446, 28.125000}};
    [self.mapView setRegion:region];
    
    NSInteger mapType = [[NSUserDefaults standardUserDefaults] integerForKey:@"mapType"];
    [self.mapView setMapType:mapType];
    [self.mapTypeSegmentController setSelectedSegmentIndex:mapType];
    
    self.annotationsShowing = [[NSUserDefaults standardUserDefaults] boolForKey:@"annotationsOn"];
    [self.sightingAnnotationsButton setSelected:self.annotationsShowing];
    
    [self reloadSightingLocations];
    
    self.heatMapShowing = [[NSUserDefaults standardUserDefaults] boolForKey:@"heatMapOverlayOn"];
    [self.mapLayerButton setSelected:self.heatMapShowing];
    
    if(self.heatMapShowing) {
        [self.mapView addOverlay:self.heatMapOverlay];
    }
}


- (void)dealloc
{
    [[NSUserDefaults standardUserDefaults] setBool:self.mapLayerButton.isSelected forKey:@"heatMapOverlayOn"];
    [[NSUserDefaults standardUserDefaults] setBool:self.sightingAnnotationsButton.isSelected forKey:@"annotationsOn"];
    [[NSUserDefaults standardUserDefaults] setInteger:self.mapTypeSegmentController.selectedSegmentIndex forKey:@"mapType"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}


- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    if (_modalView) {
        _modalView.view.frame = _modalPlaceholderView.frame;
    }
    
    UIDeviceOrientation deviceOrientation = [[UIApplication sharedApplication] statusBarOrientation];
    self.tvOverlay.image = UIInterfaceOrientationIsPortrait(deviceOrientation) ? [UIImage imageNamed:@"tvOverlayPortrait.png"] : [UIImage imageNamed:@"TVOverlay.png"];
}


- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{    
    return YES;
}


- (UIActivityIndicatorView*)annotationActivityIndicator
{
    if(!_annotationActivityIndicator) {
        _annotationActivityIndicator = [[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        [_annotationActivityIndicator setHidesWhenStopped:YES];
    }
    return _annotationActivityIndicator;
}


- (NSManagedObjectContext*)backgroundContext
{
    if(!_backgroundContext) {
        _backgroundContext = [[UFOCoreData sharedInstance] createManagedObjectContext];
    }
    return _backgroundContext;
}


- (void)modalWantsToDismiss
{
    [_modalView.view removeFromSuperview];
    _modalView = nil;
    [self.mapView setUserInteractionEnabled:YES];
}


#pragma mark - Data gathering

/**
 This function is meant to fetch all of the sighting locations stored in the database
 and provide them to the backmap to be used by - (void)updateVisibleAnnotations. This
 method will be ammeded in the future to include a predicate which will filter annotations
 
 We fetch on the background context because that portion of the function runs on a separate 
 thread. We will use the Object Id's to fetch the object on the main thread. 
 While this does not save much time currently, it will greatly reduce the work on the 
 main thread when we introduce a predicate to filter with.
 */
- (void)reloadSightingLocations;
{
    [self.loadingIndicator startAnimating];
    [self.mapView removeAnnotations:[self.mapView annotations]]; // If there are any annotations currently showing, remove them
    [_backMap removeAnnotations:[_backMap annotations]];
 
    NSFetchRequest* fetch = [[NSFetchRequest alloc]initWithEntityName:@"SightingLocation"];
    fetch.resultType = NSManagedObjectIDResultType;
    
    [[UFOCoreData sharedInstance] executeFetchRequest:fetch onBackgroundContextWithFinised:^(NSArray* objectIds){
        
        dispatch_async(title_backgrond_queue(), ^{
            for (NSManagedObjectID* objID in objectIds) {
                SightingLocation* sightingLoc = (SightingLocation*)[self.managedObjectContext objectWithID:objID];
                //*********************************
                // This is neccesary to implement the cluster annotation
                [sightingLoc setCoordinate:[sightingLoc actualCoordinate]];
                //*********************************
                [_backMap addAnnotation:sightingLoc];
            }
            
            dispatch_sync(dispatch_get_main_queue(), ^{
                if(self.annotationsShowing) {
                    [self updateVisibleAnnotations];
                }
                
                [self.loadingIndicator stopAnimating];
            });
        });
        

        
    } andFailed:nil];
}




//***************************************************************************************************
#pragma mark - IBActions
//***************************************************************************************************

/**
 We want the icon for the map to animate itself 45 degrees
 to the left on first touch. While it is rotated we slide out the 
 native map kits selections. When the user presses it again, the icon
 rotates to it's natural position. 
 @param UIbutton
 */
- (IBAction)compassButtonSelected:(UIButton *)sender 
{
    CGAffineTransform rotate = CGAffineTransformMakeRotation(DEGREES_TO_RADIANS(_mapSelectionOpen ? -45 : 45));
    CGFloat newAlpha = _mapSelectionOpen ? 0.0f : 1.0;
    
    [UIView animateWithDuration:0.3 delay:0.0f options:UIViewAnimationCurveEaseInOut animations:^{
        self.mapTypeSegmentController.alpha = newAlpha;
        self.compassButton.transform = rotate;
    } completion:^(BOOL finished){
        _mapSelectionOpen = !_mapSelectionOpen;
    }];
}


/**
 A button which romoves or adds the annotations onto the map. 
 @param UIButton
 */
- (IBAction)sightingsAnnotationsButtonSelected:(UIButton *)sender 
{
    if(self.annotationsShowing){
        [self.mapView removeAnnotations:[self.mapView annotations]];
    }
    else {
        [self updateVisibleAnnotations];
    }
    self.annotationsShowing = !self.annotationsShowing;
    [sender setSelected:self.annotationsShowing];
}


/**
 Show or hide the Heat Map Layer
 @param UIButton
 */
- (IBAction)mapLayerButtonSelected:(UIButton *)sender {
    
    if(self.heatMapShowing) {
        if([[self.mapView overlays] containsObject:self.heatMapOverlay])
            [self.mapView removeOverlay:self.heatMapOverlay];
    }
    else {
        if(![[self.mapView overlays] containsObject:self.heatMapOverlay])
            [self.mapView addOverlay:self.heatMapOverlay];
    }
    self.heatMapShowing = !self.heatMapShowing;
    [sender setSelected:self.heatMapShowing];
}


/**
 Switch to the Database Expolorer View
 @param UIButton
 */
- (IBAction)filterButtonSelected:(UIButton *)sender 
{
    if([self.delegate respondsToSelector:@selector(UFOMapViewControllerWantsToExit:)]) {
        [self.delegate UFOMapViewControllerWantsToExit:self];
    }
}


/**
 This action in meant for the "x" button on the alert view
 It will hide the alert view
 @param UIButton
 */
- (IBAction)xButtonSelected:(UIButton *)sender 
{
    [self hideAlert];
}


/**
 This action is meant to show the users location. 
 It is currently unused.
 @param UIButton
 */
- (IBAction)userLocationButtonSelected:(UIButton*)sender
{
    if([CLLocationManager locationServicesEnabled]) {
        locationManager = [[CLLocationManager alloc]init];
        locationManager.delegate = self;
        [locationManager setDistanceFilter:1000];
        [locationManager setDesiredAccuracy:kCLLocationAccuracyKilometer];
        [locationManager startUpdatingLocation];
    }
    else {
        NSLog(@"User does not allow location services");
    }
    [self.mapView setShowsUserLocation:YES];
}


/**
 This action is meant for a button on the alert view. 
 It is currently unused
 @param UIButton
 */
- (IBAction)stopFilteringSelected:(UIButton *)sender 
{
}


- (IBAction)mapTypeSegmentChanged:(UISegmentedControl *)sender 
{
    [self.mapView setMapType:[sender selectedSegmentIndex]];
}


#pragma mark - MapKit Delegate Functions

- (MKOverlayView*) mapView:(MKMapView *)mapView viewForOverlay:(id<MKOverlay>)overlay
{
    return [[UFOHeatMapOverlayView alloc] initWithOverlay:overlay];
}

/**
 This function gets called when the mapview changes region, usually due to user input. 
 We want to update the annotations each time this happens. 
 @param mapView, animated 
 */
- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated
{
    if(self.annotationsShowing) {
        _selectedAnnotationView.selected = NO;
        [self updateVisibleAnnotations];
    }
}   


/**
 This function gets called when the user taps the right arrow on an anotation which has been selected
 We want to create a MapModalView to show the sightings in this location to the user. 
 */
- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view calloutAccessoryControlTapped:(UIControl *)control
{
    _stopGettingTitle = YES;    // If working on a background thread building the title, stop.
    SightingLocation* location = view.annotation;
    _modalView = [[MapModalView alloc]initWithSightingLocation:location andPredicate:nil];
    [_modalView.view setFrame:CGRectMake(79, 124, 855, 560)];    
    [self.view insertSubview:_modalView.view belowSubview:[[self.view subviews] lastObject]];
    [self addChildViewController:_modalView];
    view.selected = NO;
}


/**
 This get called whenever an annotation gets added to the map. 
 Traditionally clustering would cause an annotation's coordinate to change to it's 
 cluster annotation, but that can be costly with a large set of annotations. 
 This is the point where we need to implement the behavior. 
 */
- (void)mapView:(MKMapView *)mapView didAddAnnotationViews:(NSArray *)views
{
    for (MKAnnotationView* annotationView in views) 
    {
        if(![annotationView.annotation isKindOfClass:[SightingLocation class]])
            continue;
        
        if(CLUSTER_ANIMATION) {
            SightingLocation* annotation = (SightingLocation*)annotationView.annotation;
           
            if(annotation.clusterAnnotation != nil) {
                CLLocationCoordinate2D containerCoordinate = annotation.clusterAnnotation.coordinate;
                annotation.clusterAnnotation = nil;
                annotation.coordinate = containerCoordinate;
                
                [UIView animateWithDuration:0.3f animations:^{
                    annotation.coordinate = [annotation actualCoordinate];
                }];
            }
            
        }
        else {
            // In place of the cluster animation we will simply fade in.
            annotationView.alpha = 0.0f;
            [UIView animateWithDuration:0.5 animations:^{
                annotationView.alpha = 1.0f;
            }];    
        }
    }
}


/**
 This function is called whenever the user selects and annotation pin. 
 The work required to count the number of cities and sighting was found
 to be too much to run on the main thread. Originally we would do all of this
 work up front for each annotation, now we only do the work we asked by the user.
 The plan is as follows
 1. Find the label we added to the leftCalloutAccessory
 2. Set the AnnotationLoading indicator to this view and start it
 3. Do work on the bg annotations thread to determine the title
 4. Return it to the main thread and stop the indicator
 */
- (void)mapView:(MKMapView *)mapView didSelectAnnotationView:(MKAnnotationView *)view
{       
    _stopGettingTitle = YES;
    _selectedAnnotationView = view;
    UILabel* label = [view.leftCalloutAccessoryView.subviews lastObject];

    [view addSubview:self.annotationActivityIndicator];
    self.annotationActivityIndicator.center = view.center;
    [self.annotationActivityIndicator startAnimating];
        
    dispatch_async(title_backgrond_queue(), ^{
        _stopGettingTitle = NO;
        SightingLocation* annotation =  view.annotation;
        NSString* newTitle = @"";
        
        NSUInteger sightingsCount = 1; 
        NSUInteger citiesCount = 1;
        if(annotation.sighting)
            sightingsCount = annotation.sighting.count;
        
        if (annotation.containedAnnotations != nil && annotation.containedAnnotations.count > 0) 
        {
            citiesCount += annotation.containedAnnotations.count;
            for (SightingLocation* location in annotation.containedAnnotations) {
                if (_stopGettingTitle) 
                    break;
                
                if(location.sighting != nil)
                    sightingsCount += location.sighting.count;
                else
                    sightingsCount += 1;
            }
            
        }
        newTitle = [NSString stringWithFormat:@"%i sightings in %i cities", sightingsCount, citiesCount];
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self.annotationActivityIndicator stopAnimating];
            [self.annotationActivityIndicator removeFromSuperview];
            
            [label setText:newTitle];
            if(_stopGettingTitle)
                [view setSelected:NO];
        });
        
    });
     
}


/**
 This is where we set up the view for each annotation.
 Adding a label to the leftcalloutview is a trick to dynamically set the title
 */
- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id <MKAnnotation>)annotation;
{
    if ([annotation isKindOfClass:[MKUserLocation class]])
        return nil;
    
    // try to dequeue an existing pin view first
    static NSString* UFOAnnotationIdentifier = @"UFOAnnotationIdentifier";
    MKPinAnnotationView* pinView = (MKPinAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:UFOAnnotationIdentifier];
    if (!pinView) {
        MKAnnotationView *annotationView = [[MKAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:UFOAnnotationIdentifier];
        annotationView.canShowCallout = YES;
        
        UIImage *UFOPin = [UIImage imageNamed:@"ufoPin.png"];
        annotationView.image = UFOPin;
        annotationView.opaque = NO;
        annotationView.rightCalloutAccessoryView = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
        
        UIView* leftCalloutView = [[UIView alloc]initWithFrame:CGRectMake(0, 0, 200, 30)];
        UILabel* label = [[UILabel alloc]initWithFrame:CGRectMake(0, 0, 200, 30)];
        [label setTextColor:[UIColor whiteColor]];
        [label setBackgroundColor:[UIColor clearColor]];
        [label setFont:[UIFont fontWithName:@"Helvetica-Bold" size:16.0f]];
        [label setTextAlignment:NSTextAlignmentCenter];
        [label setAdjustsFontSizeToFitWidth:YES];
        [label setMinimumScaleFactor:0.3];
        [leftCalloutView addSubview:label];
        annotationView.leftCalloutAccessoryView = leftCalloutView;
        return annotationView;
    }
    else {
        pinView.annotation = annotation;
    }
    return pinView;
}
//***************************************************************************************************





//***************************************************************************************************
#pragma mark - MapPin Clustering 
//***************************************************************************************************
/**
 This is the meat of the map pin clustering implementation. There are many pieces to 
 this but the plan is as follows : 
 1. Determine the MapRect currently being shown to the user
 2. create a 2D grid of the map and iterate through it. On each iteration :
    a. determine all annotations in this grid
    b. find the ~center most annotation
    c. assign all other annotations as the center most's contained annotations
    d. add the ~center most annotation to a set to be added on the main thread
    e. determine if any other annotations are currently show in this rect, add
        them to a set to be removed on the main thread
 3. Return to the main thread to do UI work
 We use a separate map called _backmap with a frame of CGRectZero to take advantage
 of the -annotationsInMapRect: apple has provided for us. 
 */
- (void)updateVisibleAnnotations
{
    dispatch_async(annotations_background_queue(), ^{
        
        /* These two sets are the goal of this function */
        NSMutableSet* setToAdd = [[NSMutableSet alloc]init];
        NSMutableSet* setToRemove = [[NSMutableSet alloc]init];

        static float marginFactor = 0;  // Used to increase/decrease the size of the map to work on
                                        // Usefull if the sample size is relatively small and you want to load
                                        // annotations which cannot be currently seen. 
        static float bucketSize = 80.0f; // This is used to determine the size of the grid sections when 
                                        // the map view gets iterated through. 
        
        /* 1. Determine the MapRect currently being shown to the user */
        MKMapRect visibleMaprect = [self.mapView visibleMapRect]; // possibly unsafe. 
        MKMapRect adjustedVisibleMapRect = MKMapRectInset(visibleMaprect, -marginFactor * visibleMaprect.size.width, -marginFactor * visibleMaprect.size.height);
        
        /* determining the coordinates for the first bucket. 
         MapKit takes care of mercator projection with    -convertPoint: toCoordinateFromView: */
        CLLocationCoordinate2D leftCoordinate =  [self.mapView convertPoint:CGPointZero toCoordinateFromView:self.view];
        CLLocationCoordinate2D rightCoordinate = [self.mapView convertPoint:CGPointMake(bucketSize, 0) toCoordinateFromView:self.view];
        
        /* gridMapRect is the iterator we will use for the map */
        double gridSize = MKMapPointForCoordinate(rightCoordinate).x - MKMapPointForCoordinate(leftCoordinate).x ;
        MKMapRect gridMapRect = MKMapRectMake(0, 0, gridSize, gridSize);
        
        double startX = floor(MKMapRectGetMinX(adjustedVisibleMapRect) / gridSize) * gridSize;
        double startY = floor(MKMapRectGetMinY(adjustedVisibleMapRect) / gridSize) * gridSize;    
        double endX = floor(MKMapRectGetMaxX(adjustedVisibleMapRect) / gridSize) * gridSize;    
        double endY = floor(MKMapRectGetMaxY(adjustedVisibleMapRect)  / gridSize) * gridSize;
        gridMapRect.origin.y = startY;
        
        /* 2. create a 2D grid of the map and iterate through it. */
        while (MKMapRectGetMinY(gridMapRect) <= endY) 
        {
            gridMapRect.origin.x = startX;
            while (MKMapRectGetMinX(gridMapRect) <= endX) 
            {

                /* a. determine all annotations in this grid */
                NSMutableSet* allAnnotationsInBucket = [[_backMap annotationsInMapRect:gridMapRect] mutableCopy];
                NSSet* visibleAnnotationsInBucket = [self.mapView annotationsInMapRect:gridMapRect];

                if(allAnnotationsInBucket.count > 0) {

                    /* b. find the ~center most annotation */ 
                    SightingLocation* annotationForGrid  = (SightingLocation*)[self centerAnnotationInGrid:gridMapRect usingAnnotations:allAnnotationsInBucket];
                                    
                    [allAnnotationsInBucket removeObject:annotationForGrid];
                    NSSet* filteredAnnotationsInBucket = allAnnotationsInBucket;
                    
                    /* c. assign all other annotations as the center most's contained annotations */
                    annotationForGrid.containedAnnotations = [filteredAnnotationsInBucket allObjects];
                          
                    /* d. add the ~center most annotation to a set to be added on the main thread */  
                    [setToAdd addObject:annotationForGrid]; // We want to do all of our UI work on the main thread
                                                            // So we add the center most point to a NSSet which
                                                            // we will add to the main map at the end of this threads
                                                            // execution 
                    
                    /* e. determine if any other annotations are currently show in this rect, add
                        them to a set to be removed on the main thread */
                    [setToRemove unionSet:visibleAnnotationsInBucket];
                    [setToRemove removeObject:annotationForGrid];

                
                    for (SightingLocation *annotation in filteredAnnotationsInBucket) {
                        annotation.clusterAnnotation = annotationForGrid;
                        annotation.containedAnnotations = nil;
                    }
                }
                
                gridMapRect.origin.x += gridSize;
            }
            
            gridMapRect.origin.y += gridSize;
        }
        
        /* 3. Return to the main thread to do UI work */
        dispatch_sync(dispatch_get_main_queue(), ^{
            
            if(CLUSTER_ANIMATION) {
                
                for (SightingLocation* annotation in setToRemove) {
                    [UIView animateWithDuration:0.3f animations:^{
                        annotation.coordinate = annotation.clusterAnnotation.coordinate;
                        
                    } completion:^(BOOL finished){
                        [self.mapView removeAnnotation:annotation];
                        annotation.coordinate = [annotation actualCoordinate];
                    }];
                }
            }
            else {
                [self.mapView removeAnnotations:[setToRemove allObjects]];
            }
            
            [self.mapView addAnnotations:[setToAdd allObjects]];
        });
    }); 
}


/**
 This function is used to find the center most point in a MKMapRect
 This function can take very long with large data sets. 
 @param gridMapRect, annotations
 @returns MKAnnotation
 */
- (id<MKAnnotation>)centerAnnotationInGrid:(MKMapRect)gridMapRect usingAnnotations:(NSSet*)annotations
{
    NSSet* visibleAnnotationsInBucket = [self.mapView annotationsInMapRect:gridMapRect];
    NSSet* annotationsForGridSet = [annotations objectsPassingTest:^BOOL(id obj, BOOL* stop){
        BOOL returnValue = ([visibleAnnotationsInBucket containsObject:obj]);
        if(returnValue)
            *stop = YES;
        return returnValue;
    }];
    
    if(annotationsForGridSet.count != 0) { return  [annotationsForGridSet anyObject]; }
    if(annotations.count < 10) { return [annotations anyObject]; }
    
    NSMutableArray* annotationsToOrder = [[annotations allObjects] mutableCopy];
  
    if(APPROXIMATE_CENTER_ANNOTATION && annotationsToOrder.count > 30) {
        [annotationsToOrder removeObjectsInRange:NSMakeRange(29, annotationsToOrder.count - 30)];
    }

    MKMapPoint centerMapPoint = MKMapPointMake(MKMapRectGetMidX(gridMapRect), MKMapRectGetMidY(gridMapRect));
    
    NSArray*  sortedAnnotations = [annotationsToOrder sortedArrayUsingComparator:^(id<MKAnnotation> obj1, id<MKAnnotation> obj2){
        MKMapPoint mapPoint1 = MKMapPointForCoordinate(obj1.coordinate);
        MKMapPoint mapPoint2 = MKMapPointForCoordinate(obj2.coordinate);
        
        CLLocationDistance distance1 = MKMetersBetweenMapPoints(mapPoint1, centerMapPoint);
        CLLocationDistance distance2 = MKMetersBetweenMapPoints(mapPoint2, centerMapPoint);
        
        if (distance1 < distance2) {
            return NSOrderedAscending;
        }
        else if (distance1 > distance2) {
            return NSOrderedDescending;
        }
        
        return NSOrderedSame;
    }];
    
    return [sortedAnnotations objectAtIndex:0];
}


#pragma mark - Alert View

- (void)showAlert
{
    if(self.alertView && self.alertView.frame.size.height == 0) {
        CGRect frame = self.alertView.frame;
        frame.size.height = 90;
        [UIView animateWithDuration:1.0f animations:^{
            self.alertView.frame = frame;
        }];
    }
}


- (void)hideAlert
{
    if(self.alertView &&  self.alertView.frame.size.height == 90) {
        CGRect frame = self.alertView.frame;
        frame.size.height = 0;
        [UIView animateWithDuration:1.0f animations:^{
            self.alertView.frame = frame;
        }];
    }
}

@end
