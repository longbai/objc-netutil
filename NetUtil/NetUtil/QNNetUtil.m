//
//  NetUtil.m
//  NetUtil
//
//  Created by bailong on 16/1/27.
//  Copyright © 2016年 Qiniu Cloud Storage. All rights reserved.
//

#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <unistd.h>
#import <arpa/inet.h>

#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <SystemConfiguration/SCNetworkReachability.h>

#import <CoreTelephony/CTCarrier.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <UIKit/UIKit.h>
#import <mach/mach.h>

#include <ifaddrs.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <sys/socket.h>

#include <resolv.h>
#include <dns.h>

#import <sys/sysctl.h>
#import <netinet/in.h>

#if TARGET_IPHONE_SIMULATOR
#include <net/route.h>
#else
#include "Route.h"
#endif /*the very same from google-code*/

#import "QNNetUtil.h"

#define ROUNDUP(a) ()

static int round_up(int l){
    return (l) > 0 ? (1 + (((l)-1) | (sizeof(long) - 1))) : sizeof(long);
}

static int localIp(char *buf){
    int err;
    int sock;
    
    // Create the UDP socket itself.
    err = 0;
    sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) {
        err = errno;
        return err;
    }
    
    struct sockaddr_in addr;
    
    memset(&addr, 0, sizeof(addr));
    
    inet_pton(AF_INET, "8.8.8.8", &addr.sin_addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(53);
    err = connect(sock, (const struct sockaddr *) &addr, sizeof(addr));
    
    if (err < 0) {
        err = errno;
    }
    
    struct sockaddr_in localAddress;
    socklen_t addressLength = sizeof(struct sockaddr_in);
    err = getsockname(sock, (struct sockaddr*)&localAddress, &addressLength);
    close(sock);
    if (err != 0) {
        return err;
    }
    const char* ip = inet_ntop(AF_INET, &(localAddress.sin_addr), buf, 32);
    if (ip == nil) {
        return -1;
    }
    return 0;
}

@implementation QNNetUtil
+ (NSString *)deviceIP{
    char buf[32] = {0};
    int err = localIp(buf);
    if (err != 0) {
        return nil;
    }
    return [NSString stringWithUTF8String:buf];
}

// ref http://stackoverflow.com/questions/4872196/how-to-get-the-wifi-gateway-address-on-the-iphone
+ (NSString *)gatewayIPAddress{
    NSString *address = nil;
    
    /* net.route.0.inet.flags.gateway */
    int mib[] = {CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_GATEWAY};
    size_t l;
    char *buf, *p;
    struct rt_msghdr *rt;
    struct sockaddr *sa;
    struct sockaddr *sa_tab[RTAX_MAX];
    int i;
    
    if (sysctl(mib, sizeof(mib) / sizeof(int), 0, &l, 0, 0) < 0) {
        address = @"192.168.0.1";
    }
    
    if (l > 0) {
        buf = malloc(l);
        if (sysctl(mib, sizeof(mib) / sizeof(int), buf, &l, 0, 0) < 0) {
            address = @"192.168.0.1";
        }
        
        for (p = buf; p < buf + l; p += rt->rtm_msglen) {
            rt = (struct rt_msghdr *)p;
            sa = (struct sockaddr *)(rt + 1);
            for (i = 0; i < RTAX_MAX; i++) {
                if (rt->rtm_addrs & (1 << i)) {
                    sa_tab[i] = sa;
                    sa = (struct sockaddr *)((char *)sa +  round_up(sa->sa_len));
                } else {
                    sa_tab[i] = NULL;
                }
            }
            
            if (((rt->rtm_addrs & (RTA_DST | RTA_GATEWAY)) == (RTA_DST | RTA_GATEWAY)) &&
                sa_tab[RTAX_DST]->sa_family == AF_INET &&
                sa_tab[RTAX_GATEWAY]->sa_family == AF_INET) {
                unsigned char octet[4] = {0, 0, 0, 0};
                int i;
                for (i = 0; i < 4; i++) {
                    octet[i] = (((struct sockaddr_in *)(sa_tab[RTAX_GATEWAY]))->sin_addr.s_addr >>
                                (i * 8)) &
                    0xFF;
                }
                if (((struct sockaddr_in *)sa_tab[RTAX_DST])->sin_addr.s_addr == 0) {
                    in_addr_t addr =
                    ((struct sockaddr_in *)(sa_tab[RTAX_GATEWAY]))->sin_addr.s_addr;
                    address =
                    [NSString stringWithFormat:@"%s", inet_ntoa(*((struct in_addr *)&addr))];
                    NSLog(@"address%@", address);
                    break;
                }
            }
        }
        free(buf);
    }
    return address;
}

+ (NSArray *)localDNSServers{
    struct __res_state res;
    
    int result = res_ninit(&res);
    NSMutableArray *servers = [[NSMutableArray alloc] init];
    if (result == 0) {
        for (int i = 0; i < res.nscount; i++) {
            NSString *s = [NSString stringWithUTF8String:inet_ntoa(res.nsaddr_list[i].sin_addr)];
            [servers addObject:s];
            NSLog(@"server : %@", s);
        }
    }
    
    res_nclose(&res);

    return [NSArray arrayWithArray:servers];
}


+ (QNNetWorkType)networkType{
    struct sockaddr_in zeroAddress;
    bzero(&zeroAddress, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;
    SCNetworkReachabilityRef defaultRouteReachability = SCNetworkReachabilityCreateWithAddress(NULL, (struct sockaddr *)&zeroAddress); //创建测试连接的引用：
    SCNetworkReachabilityFlags flags;
    SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags);
    CFRelease(defaultRouteReachability);
    if ((flags & kSCNetworkReachabilityFlagsReachable) == 0)
    {
        return QNNetWorkType_None;
    }
    QNNetWorkType retVal = QNNetWorkType_None;
    if ((flags & kSCNetworkReachabilityFlagsConnectionRequired) == 0)
    {
        retVal = QNNetWorkType_WIFI;
    }
    if ((((flags & kSCNetworkReachabilityFlagsConnectionOnDemand ) != 0) ||
         (flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0))
    {
        if ((flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0)
        {
            retVal = QNNetWorkType_WIFI;
        }
    }
    if ((flags & kSCNetworkReachabilityFlagsIsWWAN) == kSCNetworkReachabilityFlagsIsWWAN)
    {
        if((flags & kSCNetworkReachabilityFlagsReachable) == kSCNetworkReachabilityFlagsReachable) {
            if ((flags & kSCNetworkReachabilityFlagsTransientConnection) == kSCNetworkReachabilityFlagsTransientConnection) {
                retVal = QNNetWorkType_MOBILE;
                if((flags & kSCNetworkReachabilityFlagsConnectionRequired) == kSCNetworkReachabilityFlagsConnectionRequired) {
                    retVal = QNNetWorkType_MOBILE;
                }
            }
        }
    }
    return retVal;

}

+ (NSString*)networkDescription{
    QNNetWorkType type = [QNNetUtil networkType];
    if (type == QNNetWorkType_None) {
        return @"None";
    }else if(type == QNNetWorkType_WIFI){
        return @"WIFI";
    }
    
    CTTelephonyNetworkInfo *networkInfo = [[CTTelephonyNetworkInfo alloc] init];
    NSString* net = nil;
    NSString* t = networkInfo.currentRadioAccessTechnology;
    if (t != nil) {
        if (t.length > 24) {
            net = [t substringFromIndex:23];
        }else{
            net = t;
        }
        CTCarrier* c = networkInfo.subscriberCellularProvider;
        if (c != nil) {
            net = [NSString stringWithFormat:@"%@-%@-%@-%@-%@", net, c.carrierName, c.mobileCountryCode, c.mobileNetworkCode, c.isoCountryCode];
        }
        
    }
    return net;
}

// todo http://stackoverflow.com/questions/5198716/iphone-get-ssid-without-private-library
+ (NSString*)ssid{
    return @"";
}
@end
