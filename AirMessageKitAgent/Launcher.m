//
//  Laucnher.m
//  AirMessageKitAgent
//
//  Created by Cole Feuer on 2022-07-09.
//

#include "AirMessageKitAgent-Swift.h"

Agent* agent;

__attribute__((constructor))
static void launcherConstructor(int argc, const char **argv) {
	//Start AirMessageKit agent
	agent = [Agent new];
	[agent startAgent];
}
