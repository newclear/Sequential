#import "PGDocument.h"

// Models
#import "PGNode.h"
#import "PGResourceIdentifier.h"
#import "PGBookmark.h"

// Controllers
#import "PGDocumentController.h"
#import "PGBookmarkController.h"
#import "PGDisplayController.h"

// Categories
#import "NSObjectAdditions.h"

NSString *const PGDocumentSortedNodesDidChangeNotification     = @"PGDocumentSortedNodesDidChange";
NSString *const PGDocumentNodeIsViewableDidChangeNotification  = @"PGDocumentNodeIsViewableDidChange";
NSString *const PGDocumentNodeDisplayNameDidChangeNotification = @"PGDocumentNodeDisplayNameDidChange";
NSString *const PGDocumentBaseOrientationDidChangeNotification = @"PGDocumentBaseOrientationDidChange";

NSString *const PGDocumentOldSortedNodesKey = @"PGDocumentOldSortedNodes";
NSString *const PGDocumentNodeKey           = @"PGDocumentNode";

#define PGPageMenuOtherItemsCount 5
#define PGDocumentMaxCachedNodes  3

@implementation PGDocument

#pragma mark Instance Methods

- (id)initWithResourceIdentifier:(PGResourceIdentifier *)ident
{
	if((self = [self init])) {
		_node = [[PGNode alloc] initWithParentAdapter:nil document:self identifier:ident adapterClass:nil dataSource:nil load:YES];
		[self noteSortedNodesDidChange];
	}
	return self;
}
- (id)initWithURL:(NSURL *)aURL
{
	return [self initWithResourceIdentifier:[PGResourceIdentifier resourceIdentifierWithURL:aURL]];
}
- (id)initWithBookmark:(PGBookmark *)aBookmark
{
	if((self = [self initWithResourceIdentifier:[aBookmark documentIdentifier]])) {
		[self setOpenedBookmark:aBookmark];
	}
	return self;
}
- (PGResourceIdentifier *)identifier
{
	return [[self node] identifier];
}
- (PGNode *)node
{
	return [[_node retain] autorelease];
}

#pragma mark -

- (BOOL)getStoredNode:(out PGNode **)outNode
        center:(out NSPoint *)outCenter
{
	if(outNode) *outNode = _storedNode;
	if(outCenter) *outCenter = _storedCenter;
	if(_storedNode) {
		_storedNode = nil;
		return YES;
	}
	return NO;
}
- (void)storeNode:(PGNode *)node
        center:(NSPoint)center
{
	_storedNode = node;
	_storedCenter = center;
}
- (BOOL)getStoredWindowFrame:(out NSRect *)outFrame
{
	if(NSEqualRects(_storedFrame, NSZeroRect)) return NO;
	if(outFrame) *outFrame = _storedFrame;
	_storedFrame = NSZeroRect;
	return YES;
}
- (void)storeWindowFrame:(NSRect)frame
{
	NSParameterAssert(!NSEqualRects(frame, NSZeroRect));
	_storedFrame = frame;
}

#pragma mark -

- (PGNode *)initialViewableNode
{
	return [self openedBookmark] ? [[self node] nodeForBookmark:[self openedBookmark]] : [[self node] sortedViewableNodeFirst:YES];
}
- (PGBookmark *)openedBookmark
{
	return [[_openedBookmark retain] autorelease];
}
- (void)setOpenedBookmark:(PGBookmark *)aBookmark
{
	if(aBookmark == _openedBookmark) return;
	[_openedBookmark release];
	_openedBookmark = [aBookmark retain];
}
- (void)deleteOpenedBookmark
{
	[[PGBookmarkController sharedBookmarkController] removeBookmark:[self openedBookmark]];
	[self setOpenedBookmark:nil];
}

#pragma mark -

- (PGDisplayController *)displayController
{
	return [[_displayController retain] autorelease];
}
- (void)setDisplayController:(PGDisplayController *)controller
{
	if(controller == _displayController) return;
	[_displayController setActiveDocument:nil closeIfAppropriate:YES];
	[_displayController release];
	_displayController = [controller retain];
	[_displayController setActiveDocument:self closeIfAppropriate:NO];
	[_displayController synchronizeWindowTitleWithDocumentName];
}

#pragma mark -

- (NSString *)displayName
{
	return [[self identifier] displayName];
}
- (void)createUI
{
	if(![self displayController]) [self setDisplayController:[[PGDocumentController sharedDocumentController] displayControllerForNewDocument]];
	[[PGDocumentController sharedDocumentController] noteNewRecentDocument:self];
	[[self displayController] showWindow:self];
	[self deleteOpenedBookmark];
}
- (void)close
{
	[[PGDocumentController sharedDocumentController] noteNewRecentDocument:self];
	[self setDisplayController:nil];
	[[PGDocumentController sharedDocumentController] removeDocument:self];
}
- (void)validate:(BOOL)knownInvalid
{
	if(!knownInvalid && [[self node] hasViewableNodes]) return;
	[self close];
	[[PGDocumentController sharedDocumentController] removeDocument:self];
}

#pragma mark -

- (BOOL)isOnline
{
	return ![[self identifier] isFileIdentifier];
}
- (NSMenu *)pageMenu
{
	return _pageMenu;
}

#pragma mark -

- (PGOrientation)baseOrientation
{
	return _baseOrientation;
}
- (void)addToBaseOrientation:(PGOrientation)anOrientation
{
	PGOrientation const o = PGAddOrientation(_baseOrientation, anOrientation);
	if(o == _baseOrientation) return;
	_baseOrientation = o;
	[self AE_postNotificationName:PGDocumentBaseOrientationDidChangeNotification];
}

#pragma mark -

- (void)noteSortedNodesDidChange
{
	if([_pageMenu numberOfItems] < PGPageMenuOtherItemsCount) [_pageMenu addItem:[NSMenuItem separatorItem]];
	while([_pageMenu numberOfItems] > PGPageMenuOtherItemsCount) [_pageMenu removeItemAtIndex:PGPageMenuOtherItemsCount];
	[[self node] addMenuItemsToMenu:_pageMenu];
	if([_pageMenu numberOfItems] == PGPageMenuOtherItemsCount) [_pageMenu removeItemAtIndex:PGPageMenuOtherItemsCount - 1];
	[self AE_postNotificationName:PGDocumentSortedNodesDidChangeNotification];
}
- (void)noteNodeIsViewableDidChange:(PGNode *)node
{
	NSParameterAssert(node);
	[self AE_postNotificationName:PGDocumentNodeIsViewableDidChangeNotification userInfo:[NSDictionary dictionaryWithObject:node forKey:PGDocumentNodeKey]];
}
- (void)noteNodeDisplayNameDidChange:(PGNode *)node
{
	NSParameterAssert(node);
	if([self node] == node) [[self displayController] synchronizeWindowTitleWithDocumentName];
	[self AE_postNotificationName:PGDocumentNodeDisplayNameDidChangeNotification userInfo:[NSDictionary dictionaryWithObject:node forKey:PGDocumentNodeKey]];
}
- (void)noteNodeDidCache:(PGNode *)node
{
	NSParameterAssert(node);
	[_cachedNodes removeObjectIdenticalTo:node];
	[_cachedNodes insertObject:node atIndex:0];
	while([_cachedNodes count] > PGDocumentMaxCachedNodes) {
		[[_cachedNodes lastObject] clearCache];
		[_cachedNodes removeLastObject];
	}
}

#pragma mark PGPrefObject

- (void)setShowsOnScreenDisplay:(BOOL)flag
{
	[super setShowsOnScreenDisplay:flag];
	[[PGPrefObject globalPrefObject] setShowsOnScreenDisplay:flag];
}
- (void)setReadingDirection:(PGReadingDirection)aDirection
{
	[super setReadingDirection:aDirection];
	[[PGPrefObject globalPrefObject] setReadingDirection:aDirection];
}
- (void)setImageScalingMode:(PGImageScalingMode)aMode
{
	[super setImageScalingMode:aMode];
	[[PGPrefObject globalPrefObject] setImageScalingMode:aMode];
}
- (void)setImageScaleFactor:(float)aFloat
{
	[super setImageScaleFactor:aFloat];
	[[PGPrefObject globalPrefObject] setImageScaleFactor:aFloat];
}
- (void)setImageScalingConstraint:(PGImageScalingConstraint)constraint
{
	[super setImageScalingConstraint:constraint];
	[[PGPrefObject globalPrefObject] setImageScalingConstraint:constraint];
}
- (void)setSortOrder:(PGSortOrder)anOrder
{
	if([self sortOrder] != anOrder) {
		[super setSortOrder:anOrder];
		[[self node] sortOrderDidChange];
		[self noteSortedNodesDidChange];
	}
	[[PGPrefObject globalPrefObject] setSortOrder:anOrder];
}
- (void)setAnimatesImages:(BOOL)flag
{
	[super setAnimatesImages:flag];
	[[PGPrefObject globalPrefObject] setAnimatesImages:flag];
}

#pragma mark NSObject

- (id)init
{
	if((self = [super init])) {
		_pageMenu = [[[PGDocumentController sharedDocumentController] defaultPageMenu] copy];
		[_pageMenu addItem:[NSMenuItem separatorItem]];
		_cachedNodes = [[NSMutableArray alloc] init];
	}
	return self;
}
- (void)dealloc
{
	[_node release];
	[_cachedNodes release]; // Don't worry about sending -clearCache to each node because the ones that don't get deallocated with us are in active use by somebody else.
	[_openedBookmark release];
	[_displayController release];
	[_pageMenu release];
	[super dealloc];
}

@end

/*@implementation PGIndexPage

#pragma mark PGPageSubclassResponsibility Protocol

- (PGBookmark *)bookmark
{
	return [[[PGIndexBookmark alloc] initWithDocumentURL:[[self document] dynamicFileURL] pageIndex:[self unsortedIndex] pageName:[self displayName] pageIcon:[self icon]] autorelease];
}

@end

@implementation PGIndexBookmark

#pragma mark Instance Methods

- (id)initWithDocumentURL:(PG/DynamicURL *)aURL
      pageIndex:(unsigned)anInt
      pageName:(NSString *)aString
      pageIcon:(NSImage *)anImage
{
	if((self = [super init])) {
		_documentURL = [aURL copy];
		_pageIndex = anInt;
		_pageName = [aString copy];
		_pageIcon = [anImage retain];
		(void)[self isValid]; // Implicitly subscribes.
	}
	return self;
}
- (unsigned)pageIndex
{
	return _pageIndex;
}

#pragma mark -

- (void)documentEventDidOccur:(NSNotification *)aNotif
{
	[self AE_postNotificationName:PGBookmarkDidChangeNotification];
}

#pragma mark PGBookmarking Protocol

- (NSString *)pageName
{
	return [[_pageName retain] autorelease];
}
- (BOOL)isValid
{
	BOOL const isValid = [[self documentURL] staticURL] != nil;
	if(isValid && !_documentSubscription) {
		_documentSubscription = [[self documentURL] subscribe];
		[_documentSubscription AE_addObserver:self selector:@selector(documentEventDidOccur:) name:PGSubscriptionEventDidOccurNotification];
	}
	return isValid;
}

- (PG/DynamicURL *)documentURL
{
	return _documentURL;
}
- (NSURL *)openingURL
{
	return [_documentURL staticURL];
}
- (NSImage *)pageIcon
{
	return [[_pageIcon retain] autorelease];
}

#pragma mark NSCoding Protocol

- (id)initWithCoder:(NSCoder *)aCoder
{
	if((self = [super init])) {
		_documentURL = [[aCoder decodeObjectForKey:@"DocumentURL"] retain];
		if(!_documentURL) _documentURL = [[aCoder decodeObjectForKey:@"DocumentAlias"] retain];
		_pageIndex = [aCoder decodeIntForKey:@"PageIndex"];
		_pageName = [[aCoder decodeObjectForKey:@"PageName"] retain];
		_pageIcon = [[aCoder decodeObjectForKey:@"PageIcon"] retain];
		(void)[self isValid]; // Implicitly subscribes.
	}
	return self;
}
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeObject:_documentURL forKey:@"DocumentURL"];
	[aCoder encodeInt:_pageIndex forKey:@"PageIndex"];
	[aCoder encodeObject:_pageName forKey:@"PageName"];
	[aCoder encodeObject:_pageIcon forKey:@"PageIcon"];
}

#pragma mark NSObject

- (unsigned int)hash
{
	return [[self class] hash] ^ _pageIndex;
}
- (BOOL)isEqual:(id)anObject
{
	if(anObject == self) return YES;
	if(![anObject isMemberOfClass:[self class]] || [self pageIndex] != [anObject pageIndex]) return NO;
	PG/DynamicURL *const otherURL = ((PGIndexBookmark *)anObject)->_documentURL;
	return _documentURL == otherURL || [_documentURL isEqual:otherURL];
}

- (void)dealloc
{
	[self AE_removeObserver];
	[_documentURL release];
	[_documentSubscription release];
	[_pageName release];
	[_pageIcon release];
	[super dealloc];
}

@end*/
