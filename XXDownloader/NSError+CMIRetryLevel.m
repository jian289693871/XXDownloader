//
//  NSError+CMIRetryLevel.m
//  comein_finance_and_economics_iphone
//
//  Created by emsihyo on 20/7/17.
//  Copyright © 2017年 emsihyo. All rights reserved.
//

#import "NSError+CMIRetryLevel.h"

@implementation NSError (CMIRetryLevel)
- (CMIRetryLevel)cmi_retryLevel{
    if ([self.domain isEqualToString:NSURLErrorDomain]) {
        switch (self.code) {
            case NSURLErrorTimedOut:
                return CMIRetryLevelVeryHigh;
            case NSURLErrorCancelled:
            case NSURLErrorBadURL:
            case NSURLErrorUnsupportedURL:
            case NSURLErrorUserCancelledAuthentication:
                return CMIRetryLevelNever;
            default:
                return CMIRetryLevelNormal;
        }
    }
    return CMIRetryLevelNever;
}
@end
