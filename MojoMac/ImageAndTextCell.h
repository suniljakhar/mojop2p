// ImageAndTextCell.m
// Copyright (c) 2001-2004, Apple Computer, Inc., all rights reserved.
// Author: Chuck Pisula
// 
// Subclass of NSTextFieldCell which can display text and an image simultaneously.
// 
// The Apple Software is provided by Apple on an "AS IS" basis.
// APPLE MAKES NO WARRANTIES, BLAH, BLAH, BLAH...

#import <Cocoa/Cocoa.h>

@interface ImageAndTextCell : NSTextFieldCell
{
  @private
	NSImage	*image;
}

- (void)setImage:(NSImage *)anImage;
- (NSImage *)image;

- (NSSize)cellSize;

@end
