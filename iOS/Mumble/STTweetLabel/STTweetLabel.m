//
//  STTweetLabel.m
//  STTweetLabel
//
//  Created by Sebastien Thiebaud on 09/29/13.
//  Copyright (c) 2013 Sebastien Thiebaud. All rights reserved.
//

#import "STTweetLabel.h"
#import "STTweetTextStorage.h"
#import "Config.h"

#define STURLRegex @"(?i)\\b((?:[a-z][\\w-]+:(?:/{1,3}|[a-z0-9%])|www\\d{0,3}[.]|[a-z0-9.\\-]+[.][a-z]{2,4}/)(?:[^\\s()<>]+|\\(([^\\s()<>]+|(\\([^\\s()<>]+\\)))*\\))+(?:\\(([^\\s()<>]+|(\\([^\\s()<>]+\\)))*\\)|[^\\s`!()\\[\\]{};:'\".,<>?«»“”‘’]))"

@interface STTweetLabel () <UITextViewDelegate>

@property (strong) STTweetTextStorage *textStorage;
@property (strong) NSLayoutManager *layoutManager;
@property (strong) NSTextContainer *textContainer;

@property (nonatomic, strong) NSString *cleanText;

@property (strong) NSMutableArray *rangesOfHotWords;

@property (nonatomic, strong) NSDictionary *attributesText;
@property (nonatomic, strong) NSDictionary *attributesHandle;
//@property (nonatomic, strong) NSDictionary *attributesHashtag;
//@property (nonatomic, strong) NSDictionary *attributesLink;

@property (strong) UITextView *textView;

- (void)setupLabel;
- (void)determineHotWords;
//- (void)determineLinks;
- (void)updateText;

@end

@implementation STTweetLabel {
    BOOL _isTouchesMoved;
    NSRange _selectableRange;
    NSInteger _firstCharIndex;
    CGPoint _firstTouchLocation;
}

#pragma mark - Lifecycle

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    
    if (self) {
        [self setupLabel];
    }
    
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    [self setupLabel];
}

#pragma mark - Responder

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    return (action == @selector(copy:));
}

- (void)copy:(id)sender {
    [[UIPasteboard generalPasteboard] setString:[_cleanText substringWithRange:_selectableRange]];
    
    @try {
        [_textStorage removeAttribute:NSBackgroundColorAttributeName range:_selectableRange];
    } @catch (NSException *exception) {
    }
}

#pragma mark - Setup

- (void)setupLabel {
        // Set the basic properties
        [self setBackgroundColor:[UIColor clearColor]];
        [self setClipsToBounds:NO];
        [self setUserInteractionEnabled:YES];
        [self setNumberOfLines:0];
    
    _leftToRight = YES;
    _textSelectable = YES;
    _selectionColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    
    _attributesText = @{NSForegroundColorAttributeName: self.textColor, NSFontAttributeName: MUMBLE_CONTENT_TEXT_FONT};
    _attributesHandle = @{NSForegroundColorAttributeName: NAV_BAR_COLOUR, NSFontAttributeName: MUMBLE_CONTENT_TEXT_FONT};
    //_attributesHashtag = @{NSForegroundColorAttributeName: [[UIColor alloc] initWithWhite:170.0/255.0 alpha:1.0], NSFontAttributeName: [UIFont fontWithName:@"HelveticaNeue" size:14.0]};
    //_attributesLink = @{NSForegroundColorAttributeName: [[UIColor alloc] initWithRed:129.0/255.0 green:171.0/255.0 blue:193.0/255.0 alpha:1.0], NSFontAttributeName: [UIFont fontWithName:@"HelveticaNeue" size:14.0]};
    
    //self.validProtocols = @[@"http", @"https"];
}

#pragma mark - Printing and calculating text

- (void)determineHotWords {
    // Need a text
    if (_cleanText == nil)
        return;
    
    _textStorage = [[STTweetTextStorage alloc] init];
    _layoutManager = [[NSLayoutManager alloc] init];
    
    NSMutableString *tmpText = [[NSMutableString alloc] initWithString:_cleanText];
    
    // Support RTL
    if (!_leftToRight) {
        tmpText = [[NSMutableString alloc] init];
        [tmpText appendString:@"\u200F"];
        [tmpText appendString:_cleanText];
    }
    
    // Define a character set for hot characters (@ handle, # hashtag)
    NSString *hotCharacters = @"@";//#";
    NSCharacterSet *hotCharactersSet = [NSCharacterSet characterSetWithCharactersInString:hotCharacters];
    
    // Define a character set for the complete world (determine the end of the hot word)
    NSMutableCharacterSet *validCharactersSet = [NSMutableCharacterSet alphanumericCharacterSet];
    [validCharactersSet removeCharactersInString:@"!@#$%^&*()-={[]}|;:',<>.?/"];
    [validCharactersSet addCharactersInString:@"_"];
    
    _rangesOfHotWords = [[NSMutableArray alloc] init];
    
    while ([tmpText rangeOfCharacterFromSet:hotCharactersSet].location < tmpText.length) {
        NSRange range = [tmpText rangeOfCharacterFromSet:hotCharactersSet];
        
        STTweetHotWord hotWord = ' ';

        switch ([tmpText characterAtIndex:range.location]) {
            case '@':
                hotWord = STTweetHandle;
                break;
           /* case '#':
                hotWord = STTweetHashtag;
                break;*/
            default:
                break;
        }

        [tmpText replaceCharactersInRange:range withString:@"%"];
        // If the hot character is not preceded by a alphanumeric characater, ie email (sebastien@world.com)
        if (range.location > 0 && [validCharactersSet characterIsMember:[tmpText characterAtIndex:range.location - 1]])
            continue;

        // Determine the length of the hot word
        int length = (int)range.length;
        
        while (range.location + length < tmpText.length) {
            BOOL charIsMember = [validCharactersSet characterIsMember:[tmpText characterAtIndex:range.location + length]];
            
            if (charIsMember)
                length++;
            else
                break;
        }
        
        // Register the hot word and its range
        if (length > 1)
            [_rangesOfHotWords addObject:@{@"hotWord": @(hotWord), @"range": [NSValue valueWithRange:NSMakeRange(range.location, length)]}];
    }
    
    //[self determineLinks];
    [self updateText];
}

/*- (void)determineLinks {
    NSMutableString *tmpText = [[NSMutableString alloc] initWithString:_cleanText];

    NSError *regexError = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:STURLRegex options:0 error:&regexError];

    [regex enumerateMatchesInString:tmpText options:0 range:NSMakeRange(0, tmpText.length) usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        NSString *protocol = @"http";
        NSString *link = [tmpText substringWithRange:result.range];
        NSRange protocolRange = [link rangeOfString:@"://"];
        if (protocolRange.location != NSNotFound) {
            protocol = [link substringToIndex:protocolRange.location];
        }

        if ([_validProtocols containsObject:protocol.lowercaseString]) {
            [_rangesOfHotWords addObject:@{@"hotWord": @(STTweetLink), @"protocol": protocol, @"range": [NSValue valueWithRange:result.range]}];
        }
    }];
}*/

- (void)updateText
{
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:_cleanText];
    [attributedString setAttributes:_attributesText range:NSMakeRange(0, _cleanText.length)];
    
    for (NSDictionary *dictionary in _rangesOfHotWords)  {
        NSRange range = [[dictionary objectForKey:@"range"] rangeValue];
        STTweetHotWord hotWord = (STTweetHotWord)[[dictionary objectForKey:@"hotWord"] intValue];
        [attributedString setAttributes:[self attributesForHotWord:hotWord] range:range];
    }
    
    [_textStorage appendAttributedString:attributedString];
    
    _textContainer = [[NSTextContainer alloc] initWithSize:CGSizeMake(self.frame.size.width, CGFLOAT_MAX)];
    [_layoutManager addTextContainer:_textContainer];
    [_textStorage addLayoutManager:_layoutManager];

    if (_textView != nil)
        [_textView removeFromSuperview];
    
    _textView = [[UITextView alloc] initWithFrame:self.bounds textContainer:_textContainer];
    _textView.delegate = self;
    _textView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    _textView.backgroundColor = [UIColor clearColor];
    _textView.textContainer.lineFragmentPadding = 0;
    _textView.textContainerInset = UIEdgeInsetsZero;
    _textView.userInteractionEnabled = NO;
    [self addSubview:_textView];
}

#pragma mark - Public methods

- (CGSize)suggestedFrameSizeToFitEntireStringConstraintedToWidth:(CGFloat)width {
    if (_cleanText == nil)
        return CGSizeZero;

    return [_textView sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
}

- (CGSize) intrinsicContentSize {
    CGSize size = [self suggestedFrameSizeToFitEntireStringConstraintedToWidth:CGRectGetWidth(self.frame)];
    return CGSizeMake(size.width, size.height + 1);
}

#pragma mark - Private methods

- (NSArray *)hotWordsList {
    return _rangesOfHotWords;
}

#pragma mark - Setters

- (void)setText:(NSString *)text {
    [super setText:@""];
    _cleanText = text;
    [self determineHotWords];
}

- (void)setValidProtocols:(NSArray *)validProtocols {
    //_validProtocols = validProtocols;
    [self determineHotWords];
}

- (void)setAttributes:(NSDictionary *)attributes {
    if (!attributes[NSFontAttributeName]) {
        NSMutableDictionary *copy = [attributes mutableCopy];
        copy[NSFontAttributeName] = self.font;
        attributes = [NSDictionary dictionaryWithDictionary:copy];
    }
    
    if (!attributes[NSForegroundColorAttributeName]) {
        NSMutableDictionary *copy = [attributes mutableCopy];
        copy[NSForegroundColorAttributeName] = self.textColor;
        attributes = [NSDictionary dictionaryWithDictionary:copy];
    }

    _attributesText = attributes;
    
    [self determineHotWords];
}

- (void)setAttributes:(NSDictionary *)attributes hotWord:(STTweetHotWord)hotWord {
    if (!attributes[NSFontAttributeName]) {
        NSMutableDictionary *copy = [attributes mutableCopy];
        copy[NSFontAttributeName] = self.font;
        attributes = [NSDictionary dictionaryWithDictionary:copy];
    }
    
    if (!attributes[NSForegroundColorAttributeName]) {
        NSMutableDictionary *copy = [attributes mutableCopy];
        copy[NSForegroundColorAttributeName] = self.textColor;
        attributes = [NSDictionary dictionaryWithDictionary:copy];
    }
    
    switch (hotWord)  {
        case STTweetHandle:
            _attributesHandle = attributes;
            break;
        /*case STTweetHashtag:
            _attributesHashtag = attributes;
            break;
        case STTweetLink:
            _attributesLink = attributes;
            break;*/
        default:
            break;
    }
    
    [self determineHotWords];
}

- (void)setLeftToRight:(BOOL)leftToRight {
    _leftToRight = leftToRight;

    [self determineHotWords];
}

- (void)setTextAlignment:(NSTextAlignment)textAlignment {
    [super setTextAlignment:textAlignment];
    _textView.textAlignment = textAlignment;
}

- (void)setDetectionBlock:(void (^)(STTweetHotWord, NSString *, NSString *, NSRange))detectionBlock {
    if (detectionBlock) {
        _detectionBlock = [detectionBlock copy];
        self.userInteractionEnabled = YES;
    } else {
        _detectionBlock = nil;
        self.userInteractionEnabled = NO;
    }
}

- (void)setAttributedText:(NSAttributedString *)attributedText {
    self.text = attributedText.string;
    if (self.text.length > 0) {
        [self setAttributes:[attributedText attributesAtIndex:0 effectiveRange:NULL]];
    }
}

#pragma mark - Getters

- (NSString *)text {
    return _cleanText;
}

- (NSDictionary *)attributes {
    return _attributesText;
}

- (NSDictionary *)attributesForHotWord:(STTweetHotWord)hotWord {
    switch (hotWord) {
        case STTweetHandle:
            return _attributesHandle;
        /*case STTweetHashtag:
            return _attributesHashtag;
            break;
        case STTweetLink:
            return _attributesLink;
            break;*/
        default:
            return NULL;
            break;
    }
}

- (BOOL)isLeftToRight {
    return _leftToRight;
}

#pragma mark - Retrieve word after touch event

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    
    if(![self getTouchedHotword:touches]) {
        [super touchesBegan:touches withEvent:event];
    }
    
    _isTouchesMoved = NO;
    
    @try {
        [_textStorage removeAttribute:NSBackgroundColorAttributeName range:_selectableRange];
    } @catch (NSException *exception) {
    }
    
    _selectableRange = NSMakeRange(0, 0);
    _firstTouchLocation = [[touches anyObject] locationInView:_textView];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    
    if ([self getTouchedHotword:touches] == nil) {
        [super touchesMoved:touches withEvent:event];
    }
    
    if (!_textSelectable) {
        UIMenuController *menuController = [UIMenuController sharedMenuController];
        [menuController setMenuVisible:NO animated:YES];
        
        return;
    }
    
    _isTouchesMoved = YES;
    
    NSInteger charIndex = [self charIndexAtLocation:[[touches anyObject] locationInView:_textView]];
    
    @try {
        [_textStorage removeAttribute:NSBackgroundColorAttributeName range:_selectableRange];
    } @catch (NSException *exception) {
    }
    
    if (_selectableRange.length == 0) {
        _selectableRange = NSMakeRange(charIndex, 1);
        _firstCharIndex = charIndex;
    } else if (charIndex > _firstCharIndex) {
        _selectableRange = NSMakeRange(_firstCharIndex, charIndex - _firstCharIndex + 1);
    } else if (charIndex < _firstCharIndex) {
        _firstTouchLocation = [[touches anyObject] locationInView:_textView];
        
        _selectableRange = NSMakeRange(charIndex, _firstCharIndex - charIndex);
    }
    
    @try {
        [_textStorage addAttribute:NSBackgroundColorAttributeName value:_selectionColor range:_selectableRange];
    } @catch (NSException *exception) {
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    
    CGPoint touchLocation = [[touches anyObject] locationInView:self];

    if (_isTouchesMoved) {
        UIMenuController *menuController = [UIMenuController sharedMenuController];
        [menuController setTargetRect:CGRectMake(_firstTouchLocation.x, _firstTouchLocation.y, 1.0, 1.0) inView:self];
        [menuController setMenuVisible:YES animated:YES];
        
        [self becomeFirstResponder];

        return;
    }
    
    if (!CGRectContainsPoint(_textView.frame, touchLocation))
        return;

    id touchedHotword = [self getTouchedHotword:touches];
    if(touchedHotword != nil) {
        NSRange range = [[touchedHotword objectForKey:@"range"] rangeValue];
        
        _detectionBlock((STTweetHotWord)[[touchedHotword objectForKey:@"hotWord"] intValue], [_cleanText substringWithRange:range], [touchedHotword objectForKey:@"protocol"], range);
    } else {
        [super touchesEnded:touches withEvent:event];
    }
}

- (NSUInteger)charIndexAtLocation:(CGPoint)touchLocation {
    NSUInteger glyphIndex = [_layoutManager glyphIndexForPoint:touchLocation inTextContainer:_textView.textContainer];
    CGRect boundingRect = [_layoutManager boundingRectForGlyphRange:NSMakeRange(glyphIndex, 1) inTextContainer:_textView.textContainer];
    
    if (CGRectContainsPoint(boundingRect, touchLocation))
        return [_layoutManager characterIndexForGlyphAtIndex:glyphIndex];
    else
        return -1;
}

- (id)getTouchedHotword:(NSSet *)touches {
    NSUInteger charIndex = [self charIndexAtLocation:[[touches anyObject] locationInView:_textView]];
    
    for (id obj in _rangesOfHotWords) {
        NSRange range = [[obj objectForKey:@"range"] rangeValue];
        
        if (charIndex >= range.location && charIndex < range.location + range.length) {
            return obj;
        }
    }
    
    return nil;
}

@end
