//
//  MeTabViewController.h
//  Mumble
//
//  Created by Stephen Sowole on 08/11/2014.
//  Copyright (c) 2014 Stephen Sowole. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "GAITrackedViewController.h"

@interface MeTabViewController : GAITrackedViewController <UITableViewDataSource, UITableViewDelegate>

@property UITableView *tableView;


@end
