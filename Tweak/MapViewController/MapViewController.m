#import "../LocationManager/LocationManager.h"
#import "MapViewController.h"

@interface LocusMapViewController ()
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) MKPointAnnotation *currentAnnotation;
@property (nonatomic, assign) CLLocationCoordinate2D selectedCoordinate;
@property (nonatomic, assign) BOOL hasSelection;

// Location button (bottom right)
@property (nonatomic, strong) UIButton *locationButton;

// Stop button (bottom right, above location button)
@property (nonatomic, strong) UIButton *stopButton;

// Bookmarks button (right side, below stop button)
@property (nonatomic, strong) UIButton *bookmarksButton;

// Close button
@property (nonatomic, strong) UIButton *closeButton;
@end

static NSString *const LocusBookmarksStorageKey = @"LocusBookmarksStorageKey";

@interface LocusBookmarksViewController : UITableViewController
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *bookmarks;
@property (nonatomic, copy) void (^onSelect)(NSDictionary *bookmark);
@property (nonatomic, copy) void (^onRename)(NSDictionary *bookmark, NSString *newName);
@property (nonatomic, copy) void (^onDelete)(NSDictionary *bookmark);
@property (nonatomic, copy) void (^onAddRequested)(void);
@end

NSString *const LocusMapSheetDidDismissNotification = @"LocusMapSheetDidDismissNotification";

@implementation LocusMapViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.navigationController.navigationBarHidden = YES;
	self.view.backgroundColor = [UIColor systemBackgroundColor];

	[self setupMapView];
	[self setupCloseButton];
	[self setupLocationButton];
	[self setupBookmarksButton];
	[self setupStopButton];
	[self updateUIState];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
	return UIStatusBarStyleDefault;
}

- (BOOL)prefersStatusBarHidden {
	return NO;
}

- (void)viewDidDisappear:(BOOL)animated {
	[super viewDidDisappear:animated];
	if (self.isBeingDismissed || self.navigationController.isBeingDismissed) {
		[[NSNotificationCenter defaultCenter] postNotificationName:LocusMapSheetDidDismissNotification object:nil];
	}
}

#pragma mark - Setup

- (void)setupMapView {
	self.mapView = [[MKMapView alloc] init];
	self.mapView.delegate = self;
	self.mapView.showsUserLocation = YES;
	self.mapView.translatesAutoresizingMaskIntoConstraints = NO;

	// Respect system theme
	if (@available(iOS 13.0, *)) {
		self.mapView.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
	}

	UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc]
		initWithTarget:self
				action:@selector(handleLongPress:)];
	[self.mapView addGestureRecognizer:longPress];

	[self.view addSubview:self.mapView];

	// Edge-to-edge, behind status bar
	[NSLayoutConstraint activateConstraints:@[
		[self.mapView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.mapView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.mapView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.mapView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];
}

- (void)setupCloseButton {
	self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
	self.closeButton.layer.cornerRadius = 16;
	self.closeButton.layer.masksToBounds = YES;

	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
	UIImage *xImage = [UIImage systemImageNamed:@"xmark" withConfiguration:config];
	UIImage *templateImage = [xImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	if (@available(iOS 26.0, *)) {
		UIButtonConfiguration *buttonConfig = nil;
		SEL glassSelector = NSSelectorFromString(@"glassButtonConfiguration");
		if ([UIButtonConfiguration respondsToSelector:glassSelector]) {
			IMP imp = [UIButtonConfiguration methodForSelector:glassSelector];
			UIButtonConfiguration *(*func)(id, SEL) = (void *)imp;
			buttonConfig = func([UIButtonConfiguration class], glassSelector);
		}
		if (!buttonConfig) {
			buttonConfig = [UIButtonConfiguration plainButtonConfiguration];
		}
		buttonConfig.image = templateImage;
		buttonConfig.contentInsets = NSDirectionalEdgeInsetsMake(8, 8, 8, 8);
		buttonConfig.baseForegroundColor = [UIColor labelColor];

		UIBackgroundConfiguration *bg = [UIBackgroundConfiguration clearConfiguration];
		bg.cornerRadius = 16;
		bg.visualEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
		bg.strokeColor = [UIColor separatorColor];
		bg.strokeWidth = 0.5;
		buttonConfig.background = bg;

		self.closeButton.configuration = buttonConfig;
	} else if (@available(iOS 15.0, *)) {
		UIButtonConfiguration *buttonConfig = [UIButtonConfiguration plainButtonConfiguration];
		buttonConfig.image = templateImage;
		buttonConfig.contentInsets = NSDirectionalEdgeInsetsMake(8, 8, 8, 8);
		buttonConfig.baseForegroundColor = [UIColor labelColor];
		self.closeButton.configuration = buttonConfig;
	} else {
		self.closeButton.backgroundColor = [UIColor secondarySystemBackgroundColor];
		[self.closeButton setImage:templateImage forState:UIControlStateNormal];
		self.closeButton.tintColor = [UIColor labelColor];
	}
	self.closeButton.imageView.contentMode = UIViewContentModeScaleAspectFit;

	[self.closeButton addTarget:self action:@selector(dismissSelf) forControlEvents:UIControlEventTouchUpInside];

	[self.view addSubview:self.closeButton];

	UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[self.closeButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
		[self.closeButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
		[self.closeButton.widthAnchor constraintEqualToConstant:32],
		[self.closeButton.heightAnchor constraintEqualToConstant:32],
	]];
}

- (void)setupBookmarksButton {
	self.bookmarksButton = [self _makeCircleButtonWithSystemImage:@"bookmark.fill" size:18];
	self.bookmarksButton.tintColor = [UIColor systemYellowColor];
	[self.bookmarksButton addTarget:self action:@selector(bookmarksTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.bookmarksButton];

	UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[self.bookmarksButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
		[self.bookmarksButton.bottomAnchor constraintEqualToAnchor:self.locationButton.topAnchor constant:-12],
		[self.bookmarksButton.widthAnchor constraintEqualToConstant:44],
		[self.bookmarksButton.heightAnchor constraintEqualToConstant:44],
	]];
}

- (void)setupLocationButton {
	self.locationButton = [self _makeCircleButtonWithSystemImage:@"location.fill" size:22];
	self.locationButton.tintColor = [UIColor systemBlueColor];
	[self.locationButton addTarget:self action:@selector(locationButtonTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.locationButton];

	UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[self.locationButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
		[self.locationButton.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16],
		[self.locationButton.widthAnchor constraintEqualToConstant:44],
		[self.locationButton.heightAnchor constraintEqualToConstant:44],
	]];
}

- (void)setupStopButton {
	self.stopButton = [self _makeCircleButtonWithSystemImage:@"xmark" size:20];
	self.stopButton.tintColor = [UIColor systemRedColor];
	[self.stopButton addTarget:self action:@selector(stopTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.stopButton];

	UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		// Stop button above bookmarks button
		[self.stopButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
		[self.stopButton.bottomAnchor constraintEqualToAnchor:self.bookmarksButton.topAnchor constant:-12],
		[self.stopButton.widthAnchor constraintEqualToConstant:44],
		[self.stopButton.heightAnchor constraintEqualToConstant:44],
	]];
}

#pragma mark - Circle Button Factory

- (UIButton *)_makeCircleButtonWithSystemImage:(NSString *)imageName size:(CGFloat)symbolSize {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	button.translatesAutoresizingMaskIntoConstraints = NO;
	button.layer.cornerRadius = 22;
	button.layer.masksToBounds = YES;

	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:symbolSize weight:UIImageSymbolWeightMedium];
	UIImage *image = [UIImage systemImageNamed:imageName withConfiguration:config];
	UIImage *templateImage = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	if (@available(iOS 26.0, *)) {
		UIButtonConfiguration *buttonConfig = nil;
		SEL glassSelector = NSSelectorFromString(@"glassButtonConfiguration");
		if ([UIButtonConfiguration respondsToSelector:glassSelector]) {
			IMP imp = [UIButtonConfiguration methodForSelector:glassSelector];
			UIButtonConfiguration *(*func)(id, SEL) = (void *)imp;
			buttonConfig = func([UIButtonConfiguration class], glassSelector);
		}
		if (!buttonConfig) {
			buttonConfig = [UIButtonConfiguration plainButtonConfiguration];
		}
		buttonConfig.image = templateImage;
		buttonConfig.contentInsets = NSDirectionalEdgeInsetsMake(10, 10, 10, 10);
		buttonConfig.baseForegroundColor = [UIColor labelColor];

		UIBackgroundConfiguration *bg = [UIBackgroundConfiguration clearConfiguration];
		bg.cornerRadius = 22;
		bg.visualEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
		bg.strokeColor = [UIColor separatorColor];
		bg.strokeWidth = 0.5;
		buttonConfig.background = bg;

		button.configuration = buttonConfig;
	} else if (@available(iOS 15.0, *)) {
		UIButtonConfiguration *buttonConfig = [UIButtonConfiguration plainButtonConfiguration];
		buttonConfig.image = templateImage;
		buttonConfig.contentInsets = NSDirectionalEdgeInsetsMake(10, 10, 10, 10);
		buttonConfig.baseForegroundColor = [UIColor labelColor];
		button.configuration = buttonConfig;
	} else {
		button.backgroundColor = [UIColor secondarySystemBackgroundColor];
		[button setImage:templateImage forState:UIControlStateNormal];
		button.tintColor = [UIColor labelColor];
	}
	button.imageView.contentMode = UIViewContentModeScaleAspectFit;
	[button bringSubviewToFront:button.imageView];

	return button;
}

#pragma mark - Long Press to Drop Pin

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
	if (gesture.state != UIGestureRecognizerStateBegan) return;

	CGPoint point = [gesture locationInView:self.mapView];
	CLLocationCoordinate2D coord = [self.mapView convertPoint:point toCoordinateFromView:self.mapView];

	[self applyCoordinate:coord startSpoofing:YES];
}

#pragma mark - Actions

- (void)stopTapped {
	[[LocusLocationManager shared] stopSpoofing];
	[self updateUIState];
}

- (void)locationButtonTapped {
	LocusLocationManager *mgr = [LocusLocationManager shared];
	if (mgr.isSpoofing) {
		// Pan to spoofed location
		MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(mgr.fakeCoordinate, 500, 500);
		[self.mapView setRegion:region animated:YES];
	} else {
		// Pan to real user location
		if (self.mapView.userLocation.location) {
			MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(
				self.mapView.userLocation.location.coordinate, 500, 500);
			[self.mapView setRegion:region animated:YES];
		}
	}
}

#pragma mark - Bookmarks

- (NSArray<NSDictionary *> *)loadBookmarks {
	NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:LocusBookmarksStorageKey];
	if (![stored isKindOfClass:[NSArray class]]) {
		return @[];
	}
	return stored;
}

- (void)saveBookmarks:(NSArray<NSDictionary *> *)bookmarks {
	[[NSUserDefaults standardUserDefaults] setObject:bookmarks forKey:LocusBookmarksStorageKey];
}

- (void)promptAddBookmarkFromCurrentSelectionWithPresenter:(UIViewController *)presenter
												completion:(void (^)(void))completion {
	if (!self.hasSelection) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Location Selected"
																	   message:@"Press and hold on the map to pick a location first."
																preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
		[presenter presentViewController:alert animated:YES completion:nil];
		return;
	}

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save Bookmark"
																   message:@"Give this location a name."
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *_Nonnull textField) {
		textField.placeholder = @"Name";
		textField.clearButtonMode = UITextFieldViewModeWhileEditing;
	}];

	__unsafe_unretained typeof(self) weakSelf = self;
	UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
	UIAlertAction *save = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
		NSString *name = alert.textFields.firstObject.text ?: @"";
		if (name.length == 0) {
			name = @"Unnamed";
		}
		NSDictionary *bookmark = @{
			@"name": name,
			@"lat": @(weakSelf.selectedCoordinate.latitude),
			@"lon": @(weakSelf.selectedCoordinate.longitude)
		};
		NSMutableArray *bookmarks = [[weakSelf loadBookmarks] mutableCopy];
		[bookmarks addObject:bookmark];
		[weakSelf saveBookmarks:bookmarks];
		if (completion) {
			completion();
		}
	}];

	[alert addAction:cancel];
	[alert addAction:save];
	[presenter presentViewController:alert animated:YES completion:nil];
}

- (void)renameBookmark:(NSDictionary *)bookmark newName:(NSString *)newName {
	NSMutableArray *bookmarks = [[self loadBookmarks] mutableCopy];
	NSUInteger index = [bookmarks indexOfObject:bookmark];
	if (index == NSNotFound) return;
	NSMutableDictionary *updated = [bookmark mutableCopy];
	updated[@"name"] = (newName.length > 0) ? newName : @"Unnamed";
	bookmarks[index] = updated;
	[self saveBookmarks:bookmarks];
}

- (void)deleteBookmark:(NSDictionary *)bookmark {
	NSMutableArray *bookmarks = [[self loadBookmarks] mutableCopy];
	[bookmarks removeObject:bookmark];
	[self saveBookmarks:bookmarks];
}

- (void)applyCoordinate:(CLLocationCoordinate2D)coord startSpoofing:(BOOL)startSpoofing {
	self.selectedCoordinate = coord;
	self.hasSelection = YES;

	if (self.currentAnnotation) {
		[self.mapView removeAnnotation:self.currentAnnotation];
	}
	self.currentAnnotation = [[MKPointAnnotation alloc] init];
	self.currentAnnotation.coordinate = coord;
	[self.mapView addAnnotation:self.currentAnnotation];

	MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coord, 500, 500);
	[self.mapView setRegion:region animated:YES];

	if (startSpoofing) {
		[[LocusLocationManager shared] startSpoofingWithCoordinate:self.selectedCoordinate];
	}
	[self updateUIState];
}

- (void)dismissSelf {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)bookmarksTapped {
	LocusBookmarksViewController *bookmarksVC = [[LocusBookmarksViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
	bookmarksVC.bookmarks = [[self loadBookmarks] mutableCopy];
	__unsafe_unretained typeof(self) weakSelf = self;
	__unsafe_unretained LocusBookmarksViewController *weakBookmarksVC = bookmarksVC;
	bookmarksVC.onSelect = ^(NSDictionary *bookmark) {
		NSNumber *lat = bookmark[@"lat"];
		NSNumber *lon = bookmark[@"lon"];
		if (!lat || !lon) return;
		CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(lat.doubleValue, lon.doubleValue);
		[weakSelf applyCoordinate:coord startSpoofing:YES];
	};
	bookmarksVC.onRename = ^(NSDictionary *bookmark, NSString *newName) {
		[weakSelf renameBookmark:bookmark newName:newName];
	};
	bookmarksVC.onDelete = ^(NSDictionary *bookmark) {
		[weakSelf deleteBookmark:bookmark];
	};
	bookmarksVC.onAddRequested = ^{
		[weakSelf promptAddBookmarkFromCurrentSelectionWithPresenter:weakBookmarksVC completion:^{
			weakBookmarksVC.bookmarks = [[weakSelf loadBookmarks] mutableCopy];
			[weakBookmarksVC.tableView reloadData];
		}];
	};

	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:bookmarksVC];
	nav.modalPresentationStyle = UIModalPresentationPageSheet;
	[self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - MKMapViewDelegate

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
	if ([annotation isKindOfClass:[MKUserLocation class]]) return nil;

	MKMarkerAnnotationView *marker = (MKMarkerAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:@"pin"];
	if (!marker) {
		marker = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"pin"];
	} else {
		marker.annotation = annotation;
	}
	marker.markerTintColor = [UIColor systemRedColor];
	marker.glyphImage = [UIImage systemImageNamed:@"mappin"];
	marker.animatesWhenAdded = YES;
	return marker;
}

#pragma mark - UI State

- (void)updateUIState {
	LocusLocationManager *mgr = [LocusLocationManager shared];

	// Stop button
	self.stopButton.alpha = 1.0;
	self.stopButton.userInteractionEnabled = mgr.isSpoofing;
	self.stopButton.imageView.alpha = mgr.isSpoofing ? 1.0 : 0.4;
}

@end

@implementation LocusBookmarksViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Bookmarks";
	self.tableView.allowsSelection = YES;
	self.tableView.backgroundColor = [UIColor systemBackgroundColor];
	self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
		initWithBarButtonSystemItem:UIBarButtonSystemItemDone
							 target:self
							 action:@selector(doneTapped)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
		initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
							 target:self
							 action:@selector(addTapped)];
}

- (void)doneTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)addTapped {
	if (self.onAddRequested) {
		self.onAddRequested();
	}
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.bookmarks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"bookmarkCell"];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"bookmarkCell"];
	}

	NSDictionary *bookmark = self.bookmarks[indexPath.row];
	NSString *name = bookmark[@"name"] ?: @"Unnamed";
	NSNumber *lat = bookmark[@"lat"];
	NSNumber *lon = bookmark[@"lon"];
	cell.textLabel.text = name;
	if (lat && lon) {
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%.5f, %.5f", lat.doubleValue, lon.doubleValue];
	} else {
		cell.detailTextLabel.text = @"";
	}
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSDictionary *bookmark = self.bookmarks[indexPath.row];
	if (self.onSelect) {
		self.onSelect(bookmark);
	}
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *bookmark = self.bookmarks[indexPath.row];
	__unsafe_unretained typeof(self) weakSelf = self;

	UIContextualAction *rename = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
																		 title:@"Rename"
																	   handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
																		   [weakSelf promptRenameForBookmark:bookmark atIndexPath:indexPath completion:completionHandler];
																	   }];
	rename.backgroundColor = [UIColor systemBlueColor];

	UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
																		 title:@"Delete"
																	   handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
																		   if (weakSelf.onDelete) {
																			   weakSelf.onDelete(bookmark);
																		   }
																		   [weakSelf.bookmarks removeObjectAtIndex:indexPath.row];
																		   [weakSelf.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
																		   completionHandler(YES);
																	   }];

	UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[remove, rename]];
	config.performsFirstActionWithFullSwipe = NO;
	return config;
}

- (void)promptRenameForBookmark:(NSDictionary *)bookmark
					atIndexPath:(NSIndexPath *)indexPath
					 completion:(void (^)(BOOL))completionHandler {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename Bookmark"
																   message:nil
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *_Nonnull textField) {
		textField.placeholder = @"Name";
		textField.text = bookmark[@"name"] ?: @"";
		textField.clearButtonMode = UITextFieldViewModeWhileEditing;
	}];

	__unsafe_unretained typeof(self) weakSelf = self;
	UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
		completionHandler(NO);
	}];
	UIAlertAction *save = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
		NSString *newName = alert.textFields.firstObject.text ?: @"";
		if (weakSelf.onRename) {
			weakSelf.onRename(bookmark, newName);
		}
		NSMutableDictionary *updated = [bookmark mutableCopy];
		updated[@"name"] = newName.length > 0 ? newName : @"Unnamed";
		weakSelf.bookmarks[indexPath.row] = updated;
		[weakSelf.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
		completionHandler(YES);
	}];

	[alert addAction:cancel];
	[alert addAction:save];
	[self presentViewController:alert animated:YES completion:nil];
}

@end