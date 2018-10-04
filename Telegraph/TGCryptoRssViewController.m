//
//  TGCryptoRssViewController.m
//  Bettergram
//
//  Created by Dukhov Philip on 9/27/18.
//

#import "TGCryptoRssViewController.h"

#import "TGApplication.h"
#import "TGPresentation.h"
#import "MWFeedParser.h"
#import "TGAppDelegate.h"

static const CGFloat kBaseCellImageOffset = 20;
static const CGFloat kCellSmallOffset = 10;

static NSString *const kEmptyHeaderReuseIdentifier =@"EmptyHeader";


@interface TGRssCell : UITableViewCell

@property (nonatomic, strong, readonly) TGRemoteImageView *iconImageView;
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UILabel *subtitleLabel;

@property (nonatomic, assign) BOOL isVideoContent;

@end

@implementation TGRssCell

+ (NSString *)reuseIdentifier
{
    return NSStringFromClass(self);
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.clearColor;
        
        _iconImageView = [[TGRemoteImageView alloc] init];
        _iconImageView.clipsToBounds = YES;
        _iconImageView.contentMode = UIViewContentModeScaleAspectFill;
        _iconImageView.contentHints = TGRemoteImageContentHintLoadFromDiskSynchronously;
        
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = TGSystemFontOfSize(14);
        
        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font = TGSystemFontOfSize(10);
        _subtitleLabel.numberOfLines = 0;
        
        [self.contentView addSubviews:@[_iconImageView, _titleLabel, _subtitleLabel]];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.contentView.frame = UIEdgeInsetsInsetRect(self.contentView.frame, UIEdgeInsetsMake(0, kBaseCellImageOffset, 0, kBaseCellImageOffset));
    
    {
        CGRect frame = CGRectMake(0, 0, self.contentView.frame.size.height, self.contentView.frame.size.height);
        if (_isVideoContent) {
            frame.size.width *= 16.0 / 9;
        }
        else {
            frame.size.width *= 11.0 / 9;
        }
        _iconImageView.frame = frame;
    }
    
    CGRect frame = CGRectZero;
    frame.origin.x = CGRectGetMaxX(_iconImageView.frame) + kCellSmallOffset;
    CGSize maxLabelSize = CGSizeMake(self.contentView.frame.size.width - frame.origin.x, CGFLOAT_MAX);
    {
        frame.size = [_titleLabel sizeThatFits:maxLabelSize];
        frame.origin.y = self.contentView.frame.size.height - frame.size.height - 42;
        _titleLabel.frame = frame;
    }{
        frame.size = [_subtitleLabel sizeThatFits:maxLabelSize];
        frame.origin.y = CGRectGetMaxY(_titleLabel.frame) + 8;
        _subtitleLabel.frame = frame;
    }
}

@end

@interface TGOlderNewsHeaderView : UITableViewHeaderFooterView {
    UIView *_leftLineView;
    UIView *_rightLineView;
}

@property (nonatomic, strong, readonly) UILabel *label;

@end

@implementation TGOlderNewsHeaderView

+ (NSString *)reuseIdentifier
{
    return NSStringFromClass(self);
}

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier
{
    if (self = [super initWithReuseIdentifier:reuseIdentifier]) {
        self.contentView.backgroundColor = UIColor.clearColor;
        
        _label = [[UILabel alloc] init];
        _label.font = TGSystemFontOfSize(10);
        
        _rightLineView = [[UIView alloc] init];
        _leftLineView = [[UIView alloc] init];
        
        [self.contentView addSubviews:@[_label, _rightLineView, _leftLineView]];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.contentView.frame = UIEdgeInsetsInsetRect(self.contentView.frame, UIEdgeInsetsMake(0, kBaseCellImageOffset, 0, kBaseCellImageOffset));
    
    [_label sizeToFit];
    _label.center = CGPointMake(self.contentView.frame.size.width / 2, self.contentView.frame.size.height / 2);
    
    CGRect frame = CGRectMake(0, (self.contentView.frame.size.height - 1) / 2,
                              CGRectGetMinX(_label.frame) - kCellSmallOffset, 1);
    _leftLineView.frame = frame;
    frame.origin.x = CGRectGetMaxX(_label.frame) + kCellSmallOffset;
    frame.size.width = self.contentView.frame.size.width - frame.origin.x;
    _rightLineView.frame = frame;
}

- (void)setPresentation:(TGPresentation *)presentation
{
    _leftLineView.backgroundColor = _rightLineView.backgroundColor = _label.textColor = presentation.pallete.cryptoSortArrowColor;
}

@end

@interface TGCryptoRssViewController () <TGFeedParserDelegate> {
    TGListsTableView *_tableView;
    NSInteger _lastReadNewsIndex;
    NSMutableArray<MWFeedItem *> *_feedItems;
    TGOlderNewsHeaderView *_olderNewsHeaderView;
    BOOL _isVideoContent;
    TGCryptoNumberFormatter *_numberFormatter;
    __weak NSTimer *_readedTimer;
    UIBarButtonItem *_leftButtonItem;
    
    NSMutableDictionary<NSIndexPath *, NSURLSessionDataTask *> *_dataTasks;
}

@property (nonatomic, strong) TGPresentation *presentation;

@end

@implementation TGCryptoRssViewController

- (instancetype)initWithPresentation:(TGPresentation *)presentation feedParser:(TGFeedParser *)feedParser isVideoContent:(BOOL)isVideoContent
{
    if (self = [super init]) {
        _feedParser = feedParser;
        _isVideoContent = isVideoContent;
        _presentation = presentation;
        _feedItems = [NSMutableArray array];
        _dataTasks = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _numberFormatter = [[TGCryptoNumberFormatter alloc] init];
    _numberFormatter.minimumFractionDigits = 0;
    _numberFormatter.maximumFractionDigits = 2;
    
    _tableView = [[TGListsTableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    if (@available(iOS 11.0, *)) {
        _tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.backgroundColor = nil;
    _tableView.showsVerticalScrollIndicator = NO;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.sectionFooterHeight = 0;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 90;
    [_tableView registerClass:[TGRssCell class] forCellReuseIdentifier:TGRssCell.reuseIdentifier];
    
    [self setLeftBarButtonItem:_leftButtonItem = [[UIBarButtonItem alloc] initWithImage:nil
                                                                                  style:UIBarButtonItemStylePlain
                                                                                 target:self
                                                                                 action:@selector(settingsButtonTap)]
                      animated:false];
    
    _olderNewsHeaderView = [[TGOlderNewsHeaderView alloc] initWithReuseIdentifier:TGOlderNewsHeaderView.reuseIdentifier];
    
    [self.view addSubviews:@[
                             _tableView
                             ]];
    [self setPresentation:_presentation];
    [self localizationUpdated];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    _lastReadNewsIndex = 0;
    _feedParser.delegate = self;
}

- (void)viewDidDisappear:(BOOL)animated
{
    _feedParser.delegate = nil;
    
    [super viewDidDisappear:animated];
}

- (void)setPresentation:(TGPresentation *)presentation
{
    _presentation = presentation;
    
    self.view.backgroundColor = presentation.pallete.backgroundColor;
    
    [_tableView reloadData];
    [_olderNewsHeaderView setPresentation:_presentation];
    _leftButtonItem.image = _presentation.images.settingsButton;
}

- (void)localizationUpdated
{
    if (_isVideoContent) {
        self.titleText = TGLocalized(@"Crypto.Videos.Title");
        _olderNewsHeaderView.label.text = TGLocalized(@"Crypto.Videos.OlderNews");
    }
    else {
        self.titleText = TGLocalized(@"Crypto.News.Title");
        _olderNewsHeaderView.label.text = TGLocalized(@"Crypto.News.OlderNews");
    }
    [_tableView reloadData];
}

- (void)scrollToTopRequested
{
    [_tableView scrollToTop];
}

- (void)settingsButtonTap
{
    TGViewController *accountSettingsController = TGAppDelegateInstance.rootController.accountSettingsController;
    [TGAppDelegateInstance.rootController pushContentController:accountSettingsController];
    
    [accountSettingsController setTargetNavigationItem:accountSettingsController.navigationItem titleController:TGAppDelegateInstance.rootController];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)__unused tableView
{
    return _feedItems.count;
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(__unused NSInteger)section
{
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    MWFeedItem *feedItem = _feedItems[indexPath.section];
    TGRssCell *cell = (TGRssCell *)[tableView dequeueReusableCellWithIdentifier:TGRssCell.reuseIdentifier forIndexPath:indexPath];
    NSInteger tag = ++cell.tag;
    if (feedItem.thumbnailURL != nil) {
        [cell.iconImageView loadImage:feedItem.thumbnailURL filter:nil placeholder:nil];
    }
    else {
        [cell.iconImageView cancelLoading];
        cell.iconImageView.image = nil;
        NSURLSessionDataTask *task = [_feedParser fillFeedItemThumbnailFromOGImage:feedItem
                                                                         completion:^(NSString *url) {
                                                                             TGDispatchOnMainThread(^{
                                                                                 if (tag == cell.tag) {
                                                                                     [cell.iconImageView loadImage:url filter:nil placeholder:nil];
                                                                                 }
                                                                             });
                                                                         }];
        if (task != nil) {
            _dataTasks[indexPath] = task;
        }
    }
    cell.titleLabel.text = feedItem.title;
    cell.titleLabel.numberOfLines = _isVideoContent ? 2 : 3;
    NSString *middleSubtitle = @"";
    if (feedItem.viewsCount != nil) {
        middleSubtitle = [NSString stringWithFormat:@"\n%@ views", [_numberFormatter stringFromNumber:feedItem.viewsCount]];
    }
    cell.subtitleLabel.text = [NSString stringWithFormat:@"%@%@ • %@",feedItem.author, middleSubtitle, [TGStringUtils stringForShortMessageTimerSeconds:(NSUInteger)-feedItem.date.timeIntervalSinceNow]];
    cell.isVideoContent = _isVideoContent;
    cell.titleLabel.textColor = feedItem.isViewed ? _presentation.pallete.secondaryTextColor : _presentation.pallete.textColor;
    cell.subtitleLabel.textColor = _presentation.pallete.secondaryTextColor;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)__unused tableView didEndDisplayingCell:(UITableViewCell *)__unused cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    [_dataTasks[indexPath] cancel];    
    [((TGRssCell *)cell).iconImageView cancelLoading];
}

- (void)tableView:(UITableView *)__unused tableView willDisplayCell:(UITableViewCell *)__unused cell forRowAtIndexPath:(NSIndexPath *)indexPath
{    
    _feedParser.lastReadDate = _feedItems[indexPath.section].date;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    MWFeedItem *feedItem = _feedItems[indexPath.section];
    if (!feedItem.isViewed) {
        feedItem.isViewed = YES;
        [_feedParser setNeedsArchiveFeedItems];
    }
    [(TGApplication *)[UIApplication sharedApplication] openURL:[NSURL URLWithString:feedItem.link]
                                                    forceNative:true
                                                      keepStack:true];
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
}

- (CGFloat)tableView:(UITableView *)__unused tableView heightForHeaderInSection:(NSInteger)section
{
    if (section > 0 && section == _lastReadNewsIndex) {
        return 40;
    }
    return 20;
}

- (UIView *)tableView:(UITableView *)__unused tableView viewForHeaderInSection:(NSInteger)section
{
    if (section > 0 && section == _lastReadNewsIndex) {
        return _olderNewsHeaderView;
    }
    return nil;
}

#pragma mark - TGFeedParserDelegate

- (void)feedParser:(TGFeedParser *)feedParser fetchedItems:(NSArray<MWFeedItem *> *)feedItems
{
    TGDispatchOnMainThread(^{
        __block NSUInteger insertionIndex;
        for (MWFeedItem *feedItem in feedItems) {
            insertionIndex = _feedItems.count;
            [_feedItems enumerateObjectsUsingBlock:^(MWFeedItem * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                if ([obj.identifier isEqualToString:feedItem.identifier]) {
                    *stop = YES;
                    insertionIndex = NSNotFound;
                    return;
                }
                if ([obj.date compare:feedItem.date] == NSOrderedAscending) {
                    *stop = YES;
                    insertionIndex = idx;
                }
            }];
            if (insertionIndex != NSNotFound) {
                [_feedItems insertObject:feedItem atIndex:insertionIndex];
                if (feedItem.date.timeIntervalSinceNow < feedParser.lastReadDate.timeIntervalSinceNow) {
                    _lastReadNewsIndex += 1;
                }
            }
        }
        [_tableView reloadData];
    });
}

@end
