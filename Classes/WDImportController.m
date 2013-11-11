//
//  WDImportController.m
//  Brushes
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
//  Copyright (c) 2011-2013 Steve Sprang
//

#import "UIImage+Additions.h"
#import "WDAppDelegate.h"
#import "WDImportController.h"
#import "WDUtilities.h"

@interface WDImportController ()
- (WDImportController *)inkpadDirectoryImportController;
- (WDImportController *)subdirectoryImportControllerForPath:(NSString *)subdirectoryPath;
- (NSArray *)toolbarItems;
- (UIImage *) iconForPathExtension:(NSString *)pathExtension;
- (void)failedLoadingMissingSubdirectory:(NSNotification *)notification;
- (NSString *) importButtonTitle;
@end

static NSString * const kCloudThumbSizeLarge = @"large";
static NSString * const WDCloudLastPathVisited = @"WDCloudLastPathVisited";
static NSString * const WDCloudSubdirectoryMissingNotification = @"WDCloudSubdirectoryMissingNotification";

@implementation WDImportController

@synthesize remotePath = remotePath_;
@synthesize delegate;

+ (NSSet *) supportedImageFormats
{
    static NSSet *imageFormats_ = nil;
    
    if (!imageFormats_) {
        NSArray *temp = [NSArray arrayWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"ImportFormats" withExtension:@"plist"]];
        imageFormats_ = [[NSSet alloc] initWithArray:temp];
    }
    
    return imageFormats_;
}

+ (BOOL) canImportType:(NSString *)extension
{
    NSString *lowercase = [extension lowercaseString];
    
    if ([lowercase isEqualToString:@"brushes"]) {
        return YES;
    }

    return [[WDImportController supportedImageFormats] containsObject:lowercase];
}

+ (BOOL) isBrushesType:(NSString *)extension
{
    NSString *lowercase = [extension lowercaseString];
    
    if ([lowercase isEqualToString:@"brushes"]) {
        return YES;
    }
    
    return NO;
}

+ (BOOL) isImageType:(NSString *)extension
{
    NSString *lowercase = [extension lowercaseString];
    return [[WDImportController supportedImageFormats] containsObject:lowercase];
}

+ (BOOL) isFontType:(NSString *)extension
{
    return [[NSSet setWithObjects:@"ttf", @"otf", nil] containsObject:extension];
}

#pragma mark -

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil 
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (!self) {
		return nil;
		
	}
	
    self.title = NSLocalizedString(@"Cloud", @"Cloud");
    
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(failedLoadingMissingSubdirectory:) name:WDCloudSubdirectoryMissingNotification object:nil];
	
	selectedItems_ = [[NSMutableSet alloc] init];
	itemsKeyedByImagePath_ = [[NSMutableDictionary alloc] init];
	itemsFailedImageLoading_ = [[NSMutableSet alloc] init];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *basePath = [[fm URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:NULL] path];
	imageCacheDirectory_ = [basePath stringByAppendingString:@"/cloud_icons/"];
	
	BOOL isDirectory = NO;
	if (![fm fileExistsAtPath:imageCacheDirectory_ isDirectory:&isDirectory] || !isDirectory) {
		[fm createDirectoryAtPath:imageCacheDirectory_ withIntermediateDirectories:YES attributes:nil error:NULL];
	}
    
	importButton_ = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Import", @"Import")
                                                     style:UIBarButtonItemStyleDone target:self
                                                    action:@selector(importSelectedItems:)];
	self.navigationItem.rightBarButtonItem = importButton_;
    importButton_.enabled = NO;
    
    self.toolbarItems = [self toolbarItems];
	
    self.contentSizeForViewInPopover = CGSizeMake(320, 480);
    
    return self;
}

#pragma mark -

- (void) viewDidLoad
{
    self.view.backgroundColor = (WDUseModernAppearance() && !WDDeviceIsPhone()) ? nil : [UIColor whiteColor];
    [self.navigationController setToolbarHidden:NO];
}

- (void)viewWillAppear:(BOOL)animated
{
	NSString *rootPath = @"/";
	
	// first pass - push last viewed directory, or default to Inkpad directory, creating if necessary
	if (remotePath_ == nil) {
		self.remotePath = rootPath;
		isRoot_ = YES;
		
		NSString *lastPathVisited = [[NSUserDefaults standardUserDefaults] stringForKey:WDCloudLastPathVisited];
		if ([lastPathVisited isEqual:rootPath]) {
			//[activityIndicator_ startAnimating];
			//[CloudClient_	loadMetadata:remotePath_];
			
		} else if (lastPathVisited.length > 1) {
			NSString *currentPath = rootPath;
			NSArray *pathComponents = [lastPathVisited componentsSeparatedByString:@"/"];
			for (NSString *pathComponent in pathComponents) {				
				if (pathComponent.length == 0) { // first component is an empty string
					continue;
				}
				currentPath = [currentPath stringByAppendingPathComponent:pathComponent];
				WDImportController *subdirectoryImportController = [self subdirectoryImportControllerForPath:currentPath];
				[self.navigationController pushViewController:subdirectoryImportController animated:NO];
			}
			
		} else {
			WDImportController *inkpadDirectoryImportController = [self inkpadDirectoryImportController];
			[self.navigationController pushViewController:inkpadDirectoryImportController animated:NO];
		}

	// pushed or popped-to view controller
	} else {
		//[activityIndicator_ startAnimating];
		//[CloudClient_	loadMetadata:remotePath_];
	}
}

- (void)viewWillDisappear:(BOOL)animated
{
	[[NSUserDefaults standardUserDefaults] setObject:remotePath_ forKey:WDCloudLastPathVisited];
	[[NSUserDefaults standardUserDefaults] synchronize];
	[selectedItems_ removeAllObjects];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation 
{
    return YES;
}

- (void)viewDidUnload 
{
	activityIndicator_ = nil;
	contentsTable_ = nil;
}

#pragma mark -
#pragma mark UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return [CloudItems_ count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{	
	NSObject *CloudItem = CloudItems_[indexPath.row];
	UITableViewCell *cell = nil;
    BOOL isDirectory = NO;
    NSString *path = @"?.vg";
    BOOL thumbnailExists = NO;
    NSDate *lastModifiedDate = nil;
	
	if (isDirectory) {
		static NSString *kDirectoryCellIdentifier = @"kDirectoryCellIdentifier";
		cell = [tableView dequeueReusableCellWithIdentifier:kDirectoryCellIdentifier];
		if (cell == nil) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kDirectoryCellIdentifier];
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			cell.imageView.image = [UIImage imageNamed:@"cloud_icon_directory.png"];
		}
	} else {
		static NSString *kItemCellIdentifier = @"kItemCellIdentifier";
		cell = [contentsTable_ dequeueReusableCellWithIdentifier:kItemCellIdentifier];
		if (cell == nil) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kItemCellIdentifier];
		}
		
		BOOL supportedFile = [WDImportController canImportType:[path pathExtension]];
		cell.textLabel.textColor = supportedFile ? [UIColor blackColor] : [UIColor grayColor];
		cell.userInteractionEnabled = supportedFile ? YES : NO;
		cell.imageView.image = [self iconForPathExtension:[path pathExtension]];
		
		if (thumbnailExists) {
            // keep the path extension since multiple files can have the same name (with different extensions)
			NSString    *flatPath = [path stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
			NSString    *cachedImagePath = [imageCacheDirectory_ stringByAppendingString:flatPath];
			UIImage     *CloudItemIcon = [UIImage imageWithContentsOfFile:cachedImagePath];
            BOOL        outOfDate = NO;
            
			if (CloudItemIcon) {
				cell.imageView.image = CloudItemIcon;
                
                // we have a cached thumbnail, see if it's out of date relative to Cloud
                NSFileManager *fm = [NSFileManager defaultManager];
                NSDictionary *attrs = [fm attributesOfItemAtPath:cachedImagePath error:NULL];
                NSDate *cachedDate = attrs[NSFileModificationDate];
                outOfDate = !cachedDate || [cachedDate compare:lastModifiedDate] == NSOrderedAscending;
			} 
            
            if (!CloudItemIcon || outOfDate) {
				itemsKeyedByImagePath_[cachedImagePath] = CloudItem;
				//[CloudClient_ loadThumbnail:CloudItem.path ofSize:kCloudThumbSizeLarge intoPath:cachedImagePath];
            }
		}
        
        // always need to update the cell checkmark since they're reused
        [cell setAccessoryType:[selectedItems_ containsObject:CloudItem] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone];
	}

	cell.textLabel.text = [path lastPathComponent];
	return cell;
}

#pragma mark -
#pragma mark UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath 
{
	NSObject *selectedItem = CloudItems_[indexPath.row];
    BOOL isDirectory = NO;
    NSString *path = @"?.vg";

	if (isDirectory) {
		WDImportController *subdirectoryImportController = [self subdirectoryImportControllerForPath:path];
		[self.navigationController pushViewController:subdirectoryImportController animated:YES];
	} else {
		if (![selectedItems_ containsObject:selectedItem]) {
			[selectedItems_ addObject:selectedItem];
			[[tableView cellForRowAtIndexPath:indexPath] setAccessoryType:UITableViewCellAccessoryCheckmark];
		} else {
			[selectedItems_ removeObject:selectedItem];
			[[tableView cellForRowAtIndexPath:indexPath] setAccessoryType:UITableViewCellAccessoryNone];
		}
	}
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
	
	[importButton_ setTitle:[self importButtonTitle]];
	[importButton_ setEnabled:selectedItems_.count > 0 ? YES : NO];
}

#pragma mark -
#pragma mark Notifications

- (void)failedLoadingMissingSubdirectory:(NSNotification *)notification
{
	if (!isRoot_) {
		return;
	}
    
	[self.navigationController popToRootViewControllerAnimated:YES];
}

#pragma mark -

- (void) importSelectedItems:(id)sender
{
	if (delegate && [delegate respondsToSelector:@selector(importController:didSelectCloudItems:)]) {
		[delegate importController:self didSelectCloudItems:[selectedItems_ allObjects]];
	}
}

- (void) unlinkCloud:(id)sender
{
    //WDAppDelegate *appDelegate = (WDAppDelegate *) [UIApplication sharedApplication].delegate;
    //[appDelegate unlinkCloud];
}

- (void) cancel:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark -

- (WDImportController *)inkpadDirectoryImportController
{
	return [self subdirectoryImportControllerForPath:@"/Brushes"];
}

- (WDImportController *)subdirectoryImportControllerForPath:(NSString *)subdirectoryPath
{
	WDImportController *subdirectoryImportController = [[WDImportController alloc] initWithNibName:@"Import" bundle:nil];
	subdirectoryImportController.remotePath = subdirectoryPath;
	subdirectoryImportController.title = [subdirectoryPath lastPathComponent];
	subdirectoryImportController.delegate = self.delegate;

	return subdirectoryImportController;
}

- (NSArray *)toolbarItems
{
    NSArray *toolbarItems = nil;
    
    UIBarButtonItem *flexibleSpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                                       target:nil
                                                                                       action:NULL];
    
    UIBarButtonItem *unlinkButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Unlink Cloud", @"Unlink Cloud")
                                                                         style:UIBarButtonItemStyleBordered target:self
                                                                        action:@selector(unlinkCloud:)];
    
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        toolbarItems = @[flexibleSpaceItem, unlinkButtonItem];
    } else {
        UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                    target:self
                                                                                    action:@selector(cancel:)];
        
        toolbarItems = @[unlinkButtonItem, flexibleSpaceItem, cancelItem];
    }


    return toolbarItems;
}

- (NSString *) importButtonTitle
{
    NSString *title = nil;
    if (selectedItems_.count < 1) {
        title = NSLocalizedString(@"Import", @"Import");
    } else {
        NSString *format = NSLocalizedString(@"Import %lu", @"Import %lu");
        title = [NSString stringWithFormat:format, (unsigned long)selectedItems_.count];
    }
    return title;
}

- (UIImage *) iconForPathExtension:(NSString *)pathExtension
{    
    if ([WDImportController isBrushesType:pathExtension]) {
		return [UIImage imageNamed:@"cloud_icon_brushes.png"];
    } else if ([WDImportController canImportType:pathExtension]) {
		return [UIImage imageNamed:@"cloud_icon_generic.png"];
	} else {
		return [UIImage imageNamed:@"cloud_icon_unsupported.png"];
	}
}

#pragma mark -

- (void)dealloc 
{	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
