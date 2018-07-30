//
//  NSError+CMIRetryLevel.h
//  comein_finance_and_economics_iphone
//
//  Created by emsihyo on 20/7/17.
//  Copyright © 2017年 emsihyo. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(UInt64,CMIRetryLevel) {
    CMIRetryLevelVeryHigh=0ULL,
    CMIRetryLevelNormal=2ULL,
    CMIRetryLevelNever=UINT64_MAX
};

@interface NSError (CMIRetryLevel)

- (CMIRetryLevel)cmi_retryLevel;

@end
