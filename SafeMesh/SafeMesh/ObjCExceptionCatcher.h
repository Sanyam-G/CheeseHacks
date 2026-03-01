#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Catches ObjC exceptions that bypass Swift's do/catch (e.g. NSInternalInconsistencyException from MPC)
@interface ObjCExceptionCatcher : NSObject

+ (BOOL)tryBlock:(void (^)(void))block error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
