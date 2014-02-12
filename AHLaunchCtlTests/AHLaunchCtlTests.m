//
//  AHLaunchCtlTests.m
//  AHLaunchCtlTests
//
//  Created by Eldon on 2/4/14.
//  Copyright (c) 2014 Eldon Ahrold. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "AHLaunchCtl.h"
#import <ServiceManagement/ServiceManagement.h>


@interface AHLaunchCtlTests : XCTestCase

@end

@implementation AHLaunchCtlTests

- (void)setUp
{
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testExample
{
    XCTFail(@"No implementation for \"%s\"", __PRETTY_FUNCTION__);
}

-(void)testLoad
{
    NSError* error;
    AHLaunchJob* job = [AHLaunchJob new];
    job.Program = @"/bin/echo";
    job.Label = @"com.eeaapps.ls";
    job.ProgramArguments = @[@"hello"];
    job.StandardOutPath = @"/tmp/hello.txt";
    job.RunAtLoad = YES;
    [[AHLaunchCtl controler] add:job toDomain:kLCUserLaunchAgent reply:^(NSError *error) {
        XCTAssertNil(error, @"Error: %@",error.localizedDescription);
    }];
}
-(void)testUnload
{
    NSError* error;

    //XCTAssertTrue([[AHLaunchCtl controler]remove:@"com.eeaapps.ls" inDomain:kLCUserLaunchAgent error:&error], @"Error: %@",error.localizedDescription);
}

-(void)testClassLoad{
    AHLaunchJob *job = [AHLaunchCtl runningJobWithLabel:@"com.eeaapps.ls" inDomain:kLCUserLaunchAgent ];
    NSLog(@"%@",job);
    
}

-(void)testRestart{
    NSError* error;
    XCTAssertTrue([[AHLaunchCtl controler]start:@"com.eeaapps.ls" inDomain:kLCUserLaunchAgent error:&error], @"Error: %@",error.localizedDescription);
    
    XCTAssertTrue([[AHLaunchCtl controler] restart:@"com.eeaapps.ls"
                                          inDomain:kLCUserLaunchAgent
                                             error:&error],
                  @"Error: %@",error.localizedDescription);
}
@end
