#import "SkybandEcrPlugin.h"
#if __has_include(<skyband_ecr_plugin/skyband_ecr_plugin-Swift.h>)
#import <skyband_ecr_plugin/skyband_ecr_plugin-Swift.h>
#else
#import "skyband_ecr_plugin-Swift.h"
#endif

@implementation SkybandEcrPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    [SwiftSkybandEcrPlugin registerWithRegistrar:registrar];
}
@end 