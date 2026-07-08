/*
 * This file is part of LiveWallpaper – LiveWallpaper App for macOS.
 * Copyright (C) 2025 Bios thusvill
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#import "WallpaperEngine.h"
#include "DisplayObjc.h"
#include "SaveSystem.h"
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/graphics/IOGraphicsLib.h>
#include <filesystem>
#import <mach/mach.h>
#include <spawn.h>
#include <unistd.h>

namespace fs = std::filesystem;

extern char **environ;

#define THUMBNAIL_QUALITY_FACTOR 0.05f
#define QUALITY_BADGE_FONT_SIZE 48.0f

static NSString *folderPath = nil;

@implementation WallpaperEngine {
@private
  dispatch_queue_t _wallpaperQueue;
  dispatch_queue_t _thumbnailQueue;
  dispatch_semaphore_t _wallpaperSemaphore;
}

+ (instancetype)sharedEngine {
  static WallpaperEngine *sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[self alloc] init];
  });
  return sharedInstance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _generatingImages = NO;
    _generatingThumbImages = NO;
    _currentVideoPath = nil;
    _daemonPIDs = std::list<pid_t>();

    _wallpaperQueue = dispatch_queue_create("com.livewallpaper.wallpaperQueue",
                                            DISPATCH_QUEUE_CONCURRENT);
    _thumbnailQueue = dispatch_queue_create("com.livewallpaper.thumbnailQueue",
                                            DISPATCH_QUEUE_SERIAL);

    _wallpaperSemaphore = dispatch_semaphore_create(2);
      _currentWallpaper = 0;
      _wallpaperList = [NSMutableArray array];
      
    ScanDisplays();

    [self killAllDaemons];
    usleep(2);

    displays = SaveSystem::Load();

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
      
      _rotationType = (RotationType)[defaults integerForKey:@"rtype"];
      
      _rotationDelay = (int)[defaults integerForKey:@"rdelay"];
      
      if(_rotationType == 0){
          _rotationType = RotationTypeSequential;
      }
      if(_rotationDelay < 50){
          _rotationDelay = 60;
      }
      if([defaults boolForKey:@"rotation"]){
          [self startWallpaperRotation];
      }
      

    for (Display display : displays) {
      CGDirectDisplayID displayID = DisplayIDFromUUID(display.uuid);
      if ([defaults boolForKey:@"random"]) {
        [self randomWallpapersLid];
      } else {
        if (!display.videoPath.empty()) {

          [self
              startWallpaperWithPath:[NSString
                                         stringWithUTF8String:display.videoPath
                                                                  .c_str()]
                          onDisplays:@[ @(displayID) ]];
        }
      }
    }
  }
  return self;
}

- (void)randomWallpapersLid {

  NSLog(@"Applying Random Wallpapers!");

  for (Display display : displays) {

    if (!display.videoPath.empty()) {
      CGDirectDisplayID displayID = DisplayIDFromUUID(display.uuid);

      [self startWallpaperWithPath:
                [self getRandomVideoFileFromFolder:[self getFolderPath]]
                        onDisplays:@[ @(displayID) ]];
    }
  }
}

- (NSString *)getRandomVideoFileFromFolder:(NSString *)folderPath {
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSError *error = nil;

  NSArray<NSString *> *allFiles =
      [fileManager contentsOfDirectoryAtPath:folderPath error:&error];

  if (error) {
    NSLog(@"Error reading directory: %@", error.localizedDescription);
    return nil;
  }

  NSMutableArray<NSString *> *videoFiles = [NSMutableArray array];

  for (NSString *fileName in allFiles) {
    NSString *fileExtension = [[fileName pathExtension] lowercaseString];

    if ([fileExtension isEqualToString:@"mp4"] ||
        [fileExtension isEqualToString:@"mov"]) {
      NSString *fullPath = [folderPath stringByAppendingPathComponent:fileName];
      [videoFiles addObject:fullPath];
    }
  }

  if (videoFiles.count == 0) {
    return nil;
  }

  NSUInteger randomIndex = arc4random_uniform((uint32_t)videoFiles.count);
  return videoFiles[randomIndex];
}

- (void)dealloc {
  [self removeNotifications];
}

- (void)setupNotifications {
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(screensDidChange:)
             name:NSApplicationDidChangeScreenParametersNotification
           object:nil];

  [[[NSWorkspace sharedWorkspace] notificationCenter]
      addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification
                  object:nil
                   queue:[NSOperationQueue mainQueue]
              usingBlock:^(NSNotification *_Nonnull note) {
                [self handleSpaceChange:note];
              }];

  [[NSWorkspace sharedWorkspace].notificationCenter
      addObserverForName:NSWorkspaceDidWakeNotification
                  object:nil
                   queue:[NSOperationQueue mainQueue]
              usingBlock:^(NSNotification *_Nonnull note) {
                [self awakeHandle:note];
              }];
}

- (void)removeNotifications {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
  [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleSpaceChange:(NSNotification *)note {
  CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFSTR("com.live.wallpaper.spaceChanged"), NULL, NULL, true);
}

- (void)awakeHandle:(NSNotification *)note {

  if ([[NSUserDefaults standardUserDefaults] floatForKey:@"random_lid"]) {
    NSLog(@"Screen Aweaked!");
    [self randomWallpapersLid];
  }
}

- (void)screensDidChange:(NSNotification *)note {
  NSLog(@"Screens changed");
}

- (NSString *)thumbnailCachePath {
  NSArray *cacheDirs = NSSearchPathForDirectoriesInDomains(
      NSCachesDirectory, NSUserDomainMask, YES);
  NSString *systemCacheDir = cacheDirs.firstObject;
  NSString *bundleName =
      [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];

  if (!bundleName || bundleName.length == 0) {
    bundleName = @"LiveWallpaper";
  }

  NSString *thumbnailPath = [systemCacheDir
      stringByAppendingPathComponent:[NSString
                                         stringWithFormat:@"%@/thumbnails",
                                                          bundleName]];

  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:thumbnailPath]) {
    [fm createDirectoryAtPath:thumbnailPath
        withIntermediateDirectories:YES
                         attributes:nil
                              error:nil];
  }

  return thumbnailPath;
}

- (NSString *)staticWallpaperCachePath {
  NSArray *cacheDirs = NSSearchPathForDirectoriesInDomains(
      NSCachesDirectory, NSUserDomainMask, YES);
  NSString *systemCacheDir = cacheDirs.firstObject;
  NSString *bundleName =
      [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];

  if (!bundleName || bundleName.length == 0) {
    bundleName = @"LiveWallpaper";
  }

  NSString *wallpapersPath = [systemCacheDir
      stringByAppendingPathComponent:[NSString
                                         stringWithFormat:@"%@/wallpapers",
                                                          bundleName]];

  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:wallpapersPath]) {
    [fm createDirectoryAtPath:wallpapersPath
        withIntermediateDirectories:YES
                         attributes:nil
                              error:nil];
  }

  return wallpapersPath;
}

- (void)clearCache {
  NSFileManager *fileManager = [NSFileManager defaultManager];

  NSString *thumbnailPath = [self thumbnailCachePath];
  if ([fileManager fileExistsAtPath:thumbnailPath]) {
    NSError *error = nil;
    NSArray *files = [fileManager contentsOfDirectoryAtPath:thumbnailPath
                                                      error:&error];
    if (!error) {
      for (NSString *file in files) {
        NSString *filePath =
            [thumbnailPath stringByAppendingPathComponent:file];
        [fileManager removeItemAtPath:filePath error:nil];
      }
    }
  }

  NSString *staticPath = [self staticWallpaperCachePath];
  if ([fileManager fileExistsAtPath:staticPath]) {
    NSError *error = nil;
    NSArray *files = [fileManager contentsOfDirectoryAtPath:staticPath
                                                      error:&error];
    if (!error) {
      for (NSString *file in files) {
        NSString *filePath = [staticPath stringByAppendingPathComponent:file];
        [fileManager removeItemAtPath:filePath error:nil];
      }
    }
  }

  NSString *appSupportDir = [NSSearchPathForDirectoriesInDomains(
      NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
  NSString *customDir =
      [appSupportDir stringByAppendingPathComponent:@"Livewall"];

  [fileManager createDirectoryAtPath:customDir
         withIntermediateDirectories:YES
                          attributes:nil
                               error:nil];

  if ([fileManager fileExistsAtPath:customDir]) {
    NSError *error = nil;
    NSArray *files = [fileManager contentsOfDirectoryAtPath:customDir
                                                      error:&error];
    if (!error) {
      for (NSString *file in files) {
        NSString *filePath = [customDir stringByAppendingPathComponent:file];
        [fileManager removeItemAtPath:filePath error:nil];
      }
    }
  }
}
- (void)generateThumbnails {
  if (!_generatingThumbImages) {
    [self generateThumbnailsForFolder:[self getFolderPath]
                       withCompletion:^{
                         dispatch_async(dispatch_get_main_queue(), ^{
                           [[NSNotificationCenter defaultCenter]
                               postNotificationName:@"ThumbnailsGenerated"
                                             object:nil];
                         });
                       }];
  }
}
- (void)resetUserData {
  NSString *appDomain = [[NSBundle mainBundle] bundleIdentifier];
  [[NSUserDefaults standardUserDefaults]
      removePersistentDomainForName:appDomain];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)generateStaticWallpapersForFolder:(NSString *)folderPath
                           withCompletion:(void (^)(void))completion {
  if (_generatingImages) {
    if (completion)
      completion();
    return;
  }

  _generatingImages = YES;
  NSLog(@"Generating static wallpapers...");

  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *wallpaperCachePath = [self staticWallpaperCachePath];

  if (!folderPath) {
    folderPath = [self getFolderPath];
  }

  if (![fileManager fileExistsAtPath:wallpaperCachePath]) {
    [fileManager createDirectoryAtPath:wallpaperCachePath
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:nil];
  }

  NSArray<NSString *> *files = [fileManager contentsOfDirectoryAtPath:folderPath
                                                                error:nil];
  if (files.count == 0) {
    NSLog(@"No files found in folder: %@", folderPath);
    _generatingImages = NO;
    if (completion)
      completion();
    return;
  }

  __block NSInteger completedCount = 0;
  NSInteger totalCount = 0;

  for (NSString *filename in files) {
    if (![filename.pathExtension.lowercaseString isEqualToString:@"mp4"] &&
        ![filename.pathExtension.lowercaseString isEqualToString:@"mov"]) {
      continue;
    }
    totalCount++;

    dispatch_async(_wallpaperQueue, ^{
      dispatch_semaphore_wait(self->_wallpaperSemaphore, DISPATCH_TIME_FOREVER);

      @autoreleasepool {
        NSString *filePath =
            [folderPath stringByAppendingPathComponent:filename];
        NSURL *videoURL = [NSURL fileURLWithPath:filePath];

        AVAsset *asset = [AVAsset assetWithURL:videoURL];

        [asset
            loadValuesAsynchronouslyForKeys:@[ @"tracks" ]
                          completionHandler:^{
                            AVKeyValueStatus status =
                                [asset statusOfValueForKey:@"tracks" error:nil];
                            if (status != AVKeyValueStatusLoaded) {
                              NSLog(@"Failed to load tracks for %@", filename);
                              completedCount++;
                              dispatch_semaphore_signal(
                                  self->_wallpaperSemaphore);
                              return;
                            }

                            [self generateStaticImageFromAsset:asset
                                                      filename:filename
                                                 wallpaperPath:
                                                     wallpaperCachePath];

                            completedCount++;

                            if (completedCount >= totalCount) {
                              self->_generatingImages = NO;
                              if (completion) {
                                dispatch_async(dispatch_get_main_queue(),
                                               completion);
                              }
                            }

                            dispatch_semaphore_signal(
                                self->_wallpaperSemaphore);
                          }];
      }
    });
  }

  if (totalCount == 0) {
    _generatingImages = NO;
    if (completion)
      completion();
  }
}

- (void)generateStaticImageFromAsset:(AVAsset *)asset
                            filename:(NSString *)filename
                       wallpaperPath:(NSString *)wallpaperPath {
  AVAssetImageGenerator *generator =
      [[AVAssetImageGenerator alloc] initWithAsset:asset];
  generator.appliesPreferredTrackTransform = YES;

  NSArray<AVAssetTrack *> *videoTracks =
      [asset tracksWithMediaType:AVMediaTypeVideo];

  if (videoTracks.count > 0) {
    AVAssetTrack *track = videoTracks.firstObject;
    CGSize videoSize = track.naturalSize;
    CGAffineTransform transform = track.preferredTransform;
    CGSize renderSize = CGSizeApplyAffineTransform(videoSize, transform);
    generator.maximumSize =
        CGSizeMake(fabs(renderSize.width), fabs(renderSize.height));
  }

  Float64 midpointSec = CMTimeGetSeconds(asset.duration) / 2.0;
  CMTime midpoint =
      CMTimeMakeWithSeconds(midpointSec, asset.duration.timescale);

  [generator
      generateCGImagesAsynchronouslyForTimes:@[ [NSValue
                                                 valueWithCMTime:midpoint] ]
                           completionHandler:^(
                               CMTime requestedTime, CGImageRef image,
                               CMTime actualTime,
                               AVAssetImageGeneratorResult result,
                               NSError *error) {
                             if (result == AVAssetImageGeneratorSucceeded &&
                                 image != NULL) {
                               CGImageRef retainedImage =
                                   CGImageCreateCopy(image);

                               NSString *thumbName =
                                   [[filename stringByDeletingPathExtension]
                                       stringByAppendingPathExtension:@"png"];
                               NSString *thumbPath = [wallpaperPath
                                   stringByAppendingPathComponent:thumbName];
                               NSURL *thumbURL =
                                   [NSURL fileURLWithPath:thumbPath];

                               CGImageDestinationRef dest =
                                   CGImageDestinationCreateWithURL(
                                       (__bridge CFURLRef)thumbURL,
                                       (__bridge CFStringRef)
                                           UTTypePNG.identifier,
                                       1, NULL);

                               if (dest) {
                                 CGImageDestinationAddImage(dest, retainedImage,
                                                            NULL);
                                 CGImageDestinationFinalize(dest);
                                 CFRelease(dest);
                               }

                               CGImageRelease(retainedImage);
                             }
                           }];
}

- (void)generateThumbnailsForFolder:(NSString *)folderPath
                     withCompletion:(void (^)(void))completion {

  // Use atomic operation to prevent race condition
  @synchronized(self) {
    if (_generatingThumbImages) {
      NSLog(@"Thumbnail generation already in progress, skipping...");
      if (completion)
        completion();
      return;
    }
    _generatingThumbImages = YES;
  }

  NSString *thumbnailCachePath = [self thumbnailCachePath];
  NSLog(@"Generating Thumbnails in %@ ...", thumbnailCachePath);

  NSFileManager *fileManager = [NSFileManager defaultManager];

  if (![fileManager fileExistsAtPath:thumbnailCachePath]) {
    [fileManager createDirectoryAtPath:thumbnailCachePath
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:nil];
  }

  NSArray<NSString *> *files = [fileManager contentsOfDirectoryAtPath:folderPath
                                                                error:nil];
  if (files.count == 0) {
    NSLog(@"No files found in folder: %@", folderPath);
    _generatingThumbImages = NO;
    if (completion)
      completion();
    return;
  }

  // Filter video files and check which need thumbnails
  NSMutableArray<NSString *> *filesToProcess = [NSMutableArray array];
  for (NSString *filename in files) {
    if (![filename.pathExtension.lowercaseString isEqualToString:@"mp4"] &&
        ![filename.pathExtension.lowercaseString isEqualToString:@"mov"]) {
      continue;
    }

    // Check if thumbnail already exists
    NSString *thumbName = [[filename stringByDeletingPathExtension]
        stringByAppendingPathExtension:@"png"];
    NSString *thumbPath =
        [thumbnailCachePath stringByAppendingPathComponent:thumbName];

    BOOL isDir;
    NSLog(@"THUMB CHECK:\n  filename: %@\n  thumbPath: %@\n  exists: %d isDir: "
          @"%d",
          filename, thumbPath,
          [fileManager fileExistsAtPath:thumbPath isDirectory:&isDir], isDir);

    if (![fileManager fileExistsAtPath:thumbPath]) {
      [filesToProcess addObject:filename];
    }
  }

  if (filesToProcess.count == 0) {
    NSLog(@"All thumbnails already exist");
    _generatingThumbImages = NO;
    if (completion)
      completion();
    return;
  }

  NSLog(@"Processing %lu videos for thumbnails",
        (unsigned long)filesToProcess.count);

  // Use block-scoped variable for counting
  __block NSInteger completedCount = 0;
  NSInteger totalCount = filesToProcess.count;

  for (NSString *filename in filesToProcess) {
    // Each file is dispatched onto the SERIAL _thumbnailQueue. The actual
    // frame extraction happens synchronously (copyCGImageAtTime:) inside
    // -extractAndSaveThumbnailForAsset:filename:thumbnailPath:, so the serial
    // queue genuinely processes one file's decode at a time instead of every
    // generator racing concurrently, which is what starved VideoToolbox
    // decode sessions on some machines (some tiles succeeded, some silently
    // never called back). That synchronous work is run on a background
    // utility queue and awaited here with a hard 15s timeout, so a single
    // hung decode can never block this queue forever, and
    // _generatingThumbImages can never get stuck at YES.
    dispatch_async(_thumbnailQueue, ^{
      @autoreleasepool {
        NSString *filePath =
            [folderPath stringByAppendingPathComponent:filename];
        NSURL *videoURL = [NSURL fileURLWithPath:filePath];

        void (^finishFile)(void) = ^{
          @synchronized(self) {
            completedCount++;
            if (completedCount >= totalCount) {
              self->_generatingThumbImages = NO;
              if (completion) {
                dispatch_async(dispatch_get_main_queue(), completion);
              }
            }
          }
        };

        if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
          NSLog(@"Video not found: %@", filePath);
          finishFile();
          return;
        }

        AVAsset *asset = [AVAsset assetWithURL:videoURL];

        // `raceLock`/`settled` guard against the timeout path and the actual
        // worker both trying to finish/count this file: whichever gets there
        // first wins, the other is a no-op.
        dispatch_semaphore_t doneSem = dispatch_semaphore_create(0);
        NSObject *raceLock = [NSObject new];
        __block BOOL settled = NO;

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
          @autoreleasepool {
            [self extractAndSaveThumbnailForAsset:asset
                                          filename:filename
                                     thumbnailPath:thumbnailCachePath];
            @synchronized(raceLock) {
              if (!settled) {
                settled = YES;
                dispatch_semaphore_signal(doneSem);
              }
            }
          }
        });

        dispatch_semaphore_wait(
            doneSem,
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC)));

        BOOL timedOut = NO;
        @synchronized(raceLock) {
          if (!settled) {
            settled = YES;
            timedOut = YES;
          }
        }

        if (timedOut) {
          NSLog(@"Thumbnail generation TIMED OUT (>15s) for %@ - writing "
                @"fallback placeholder",
                filename);
          [self writeFallbackThumbnailForFilename:filename
                                     thumbnailPath:thumbnailCachePath];
        }

        finishFile();
      }
    });
  }
}

// Loads video track/duration metadata and extracts a representative frame
// for `asset`, writing it as a PNG at <thumbnailPath>/<filename base>.png.
// Tries the clip midpoint first, then falls back to t=0 and t=1s if the seek
// fails - some H.264 4K files fail to decode at an arbitrary midpoint on
// certain machines but succeed near a keyframe. Posts `ThumbnailSaved` on
// success. If every attempt fails, writes a placeholder PNG instead of
// leaving the tile stuck on an infinite spinner.
//
// This method performs blocking/synchronous AVFoundation calls on purpose
// (it is expected to run on a background queue); the caller is responsible
// for bounding how long it waits for this to return.
- (void)extractAndSaveThumbnailForAsset:(AVAsset *)asset
                                filename:(NSString *)filename
                           thumbnailPath:(NSString *)thumbnailPath {
  NSString *thumbName = [[filename stringByDeletingPathExtension]
      stringByAppendingPathExtension:@"png"];
  NSString *thumbPath =
      [thumbnailPath stringByAppendingPathComponent:thumbName];

  // Whole-folder path keeps its placeholder-on-failure behavior so tiles never
  // stay on an infinite spinner. The per-file API deliberately does NOT do this
  // (see -generateThumbnailForVideoPath:...), so it delegates to the shared core
  // and decides for itself.
  BOOL ok = [self extractThumbnailFromAsset:asset
                          toDestinationPath:thumbPath
                                      label:filename];
  if (!ok) {
    [self writeFallbackThumbnailForFilename:filename
                               thumbnailPath:thumbnailPath];
  }
}

// Core frame-extraction shared by the whole-folder path and the per-file API.
// Reads frames from `asset` and, on success, writes a PNG to the EXPLICIT
// destination file `destPath`, posts `ThumbnailSaved` for that path, and
// returns YES. On any failure returns NO WITHOUT writing any placeholder — the
// caller decides whether a placeholder is appropriate. `label` is used only for
// logging.
//
// This method performs blocking/synchronous AVFoundation calls on purpose (it
// is expected to run on a background queue); the caller is responsible for
// bounding how long it waits for this to return. Seek strategy: clip midpoint
// first (best representative frame), then t=0, then ~1s in, since some 4K H.264
// files fail to decode at an arbitrary midpoint on certain machines but succeed
// near a keyframe.
- (BOOL)extractThumbnailFromAsset:(AVAsset *)asset
                toDestinationPath:(NSString *)destPath
                            label:(NSString *)label {
  NSURL *thumbURL = [NSURL fileURLWithPath:destPath];

  NSArray<AVAssetTrack *> *videoTracks =
      [asset tracksWithMediaType:AVMediaTypeVideo];
  if (videoTracks.count == 0) {
    NSLog(@"No video track for %@", label);
    return NO;
  }

  CMTime duration = asset.duration;
  Float64 durationSeconds = CMTimeGetSeconds(duration);
  if (!CMTIME_IS_VALID(duration) || isnan(durationSeconds) ||
      durationSeconds <= 0) {
    NSLog(@"Invalid duration for %@", label);
    return NO;
  }

  AVAssetImageGenerator *generator =
      [[AVAssetImageGenerator alloc] initWithAsset:asset];
  generator.appliesPreferredTrackTransform = YES;
  // Allow the generator to snap to the closest available keyframe instead of
  // failing outright when it can't decode the exact requested time.
  generator.requestedTimeToleranceBefore = kCMTimePositiveInfinity;
  generator.requestedTimeToleranceAfter = kCMTimePositiveInfinity;

  AVAssetTrack *track = videoTracks.firstObject;
  CGSize naturalSize = track.naturalSize;
  CGAffineTransform transform = track.preferredTransform;
  CGSize renderSize = CGSizeApplyAffineTransform(naturalSize, transform);
  generator.maximumSize =
      CGSizeMake(fabs(renderSize.width * THUMBNAIL_QUALITY_FACTOR),
                 fabs(renderSize.height * THUMBNAIL_QUALITY_FACTOR));

  // Multi-step fallback seek times: midpoint first (best representative
  // frame), then the very start, then ~1s in, in case the midpoint lands on
  // a spot the decoder chokes on for this particular file.
  NSArray<NSNumber *> *candidateSeconds = @[
    @(durationSeconds / 2.0), @(0.0), @(MIN(1.0, durationSeconds))
  ];

  CGImageRef resultImage = NULL;
  for (NSNumber *secondsValue in candidateSeconds) {
    CMTime targetTime =
        CMTimeMakeWithSeconds(secondsValue.doubleValue, duration.timescale);
    NSError *genError = nil;
    CMTime actualTime = kCMTimeZero;
    CGImageRef image = [generator copyCGImageAtTime:targetTime
                                          actualTime:&actualTime
                                               error:&genError];
    if (image != NULL) {
      resultImage = image;
      break;
    }
    NSLog(@"Thumbnail seek attempt at %.2fs failed for %@: %@",
          secondsValue.doubleValue, label, genError.localizedDescription);
  }

  if (resultImage == NULL) {
    NSLog(@"Thumbnail generation failed for %@ after all seek attempts", label);
    return NO;
  }

  CGImageDestinationRef dest = CGImageDestinationCreateWithURL(
      (__bridge CFURLRef)thumbURL, (__bridge CFStringRef)UTTypePNG.identifier,
      1, NULL);
  BOOL wrote = NO;
  if (dest) {
    CGImageDestinationAddImage(dest, resultImage, NULL);
    wrote = CGImageDestinationFinalize(dest);
    CFRelease(dest);
  }
  CGImageRelease(resultImage);

  if (!wrote) {
    NSLog(@"Failed to write PNG thumbnail: %@", destPath);
    return NO;
  }

  NSLog(@"Saved PNG thumbnail: %@", destPath);
  [self postThumbnailSavedNotificationForPath:destPath];
  return YES;
}

// Per-file, lazy thumbnail generation used by the cloud-drive grid path. See
// the header for the full contract. `readPath` is always a readable LOCAL path
// (the Swift caller has already materialized any cloud/dataless file to a temp
// file). This method is independent of the `_generatingThumbImages` latch used
// by the whole-folder path, so a folder batch in flight never blocks it and it
// never blocks a batch.
- (void)generateThumbnailForVideoPath:(NSString *)readPath
                    thumbnailFilePath:(NSString *)thumbnailFilePath
                           completion:(void (^)(BOOL ok))completion {
  // Guarantee `completion` fires exactly once, on the main queue.
  __block BOOL completionFired = NO;
  void (^finish)(BOOL) = ^(BOOL ok) {
    @synchronized(self) {
      if (completionFired)
        return;
      completionFired = YES;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      if (completion)
        completion(ok);
    });
  };

  NSFileManager *fileManager = [NSFileManager defaultManager];

  // Already cached on disk -> immediate success, no work.
  if ([fileManager fileExistsAtPath:thumbnailFilePath]) {
    finish(YES);
    return;
  }

  dispatch_async(_thumbnailQueue, ^{
    @autoreleasepool {
      if (![[NSFileManager defaultManager] fileExistsAtPath:readPath]) {
        NSLog(@"Per-file thumbnail: source not found: %@", readPath);
        finish(NO);
        return;
      }

      // Ensure the destination directory exists so the PNG write can succeed.
      NSString *destDir =
          [thumbnailFilePath stringByDeletingLastPathComponent];
      if (destDir.length > 0 &&
          ![[NSFileManager defaultManager] fileExistsAtPath:destDir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:destDir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
      }

      NSURL *videoURL = [NSURL fileURLWithPath:readPath];
      AVAsset *asset = [AVAsset assetWithURL:videoURL];
      NSString *label = readPath.lastPathComponent;

      // Run the synchronous extraction on a background utility queue and await
      // it with a per-file timeout so a single hung decode can never wedge the
      // serial thumbnail queue. `raceLock`/`settled` ensure the worker and the
      // timeout path never both count this file.
      dispatch_semaphore_t doneSem = dispatch_semaphore_create(0);
      NSObject *raceLock = [NSObject new];
      __block BOOL settled = NO;
      __block BOOL extractOK = NO;

      dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
          BOOL ok = [self extractThumbnailFromAsset:asset
                                  toDestinationPath:thumbnailFilePath
                                              label:label];
          @synchronized(raceLock) {
            if (!settled) {
              settled = YES;
              extractOK = ok;
              dispatch_semaphore_signal(doneSem);
            }
          }
        }
      });

      // readPath is always local, so 15s is a generous bound.
      dispatch_semaphore_wait(
          doneSem,
          dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC)));

      BOOL timedOut = NO;
      BOOL ok = NO;
      @synchronized(raceLock) {
        if (!settled) {
          settled = YES;
          timedOut = YES;
        } else {
          ok = extractOK;
        }
      }

      if (timedOut) {
        // CRITICAL: do NOT write a placeholder PNG here — leaving one at
        // thumbnailFilePath would make future retries get skipped. Just fail so
        // the caller can retry later.
        NSLog(@"Per-file thumbnail TIMED OUT (>15s) for %@ - reporting failure "
              @"(no placeholder written)",
              label);
        finish(NO);
        return;
      }

      if (!ok) {
        NSLog(@"Per-file thumbnail extraction failed for %@ (no placeholder "
              @"written)",
              label);
      }
      finish(ok);
    }
  });
}

// Writes a simple dark-gray placeholder PNG so a tile never shows an
// infinite spinner when real frame extraction fully fails. Posts the same
// `ThumbnailSaved` notification as a real thumbnail so the tile refreshes;
// the real failure reason was already NSLog'd by the caller for debugging.
- (void)writeFallbackThumbnailForFilename:(NSString *)filename
                             thumbnailPath:(NSString *)thumbnailPath {
  NSString *thumbName = [[filename stringByDeletingPathExtension]
      stringByAppendingPathExtension:@"png"];
  NSString *thumbPath =
      [thumbnailPath stringByAppendingPathComponent:thumbName];
  NSURL *thumbURL = [NSURL fileURLWithPath:thumbPath];

  size_t width = 320;
  size_t height = 180;
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGContextRef context =
      CGBitmapContextCreate(NULL, width, height, 8, 0, colorSpace,
                            kCGImageAlphaPremultipliedLast);
  CGColorSpaceRelease(colorSpace);

  if (!context) {
    NSLog(@"Failed to create fallback thumbnail context for %@", filename);
    return;
  }

  CGContextSetRGBFillColor(context, 0.2, 0.2, 0.2, 1.0);
  CGContextFillRect(context, CGRectMake(0, 0, width, height));

  CGImageRef placeholder = CGBitmapContextCreateImage(context);
  CGContextRelease(context);

  if (!placeholder) {
    NSLog(@"Failed to render fallback thumbnail image for %@", filename);
    return;
  }

  CGImageDestinationRef dest = CGImageDestinationCreateWithURL(
      (__bridge CFURLRef)thumbURL, (__bridge CFStringRef)UTTypePNG.identifier,
      1, NULL);
  BOOL wrote = NO;
  if (dest) {
    CGImageDestinationAddImage(dest, placeholder, NULL);
    wrote = CGImageDestinationFinalize(dest);
    CFRelease(dest);
  }
  CGImageRelease(placeholder);

  if (wrote) {
    NSLog(@"Saved fallback placeholder thumbnail: %@", thumbName);
    [self postThumbnailSavedNotificationForPath:thumbPath];
  } else {
    NSLog(@"Failed to write fallback placeholder thumbnail: %@", thumbName);
  }
}

// Shared by both the real and fallback-placeholder success paths so tiles
// refresh incrementally instead of waiting for the whole-batch
// `ThumbnailsGenerated` notification.
- (void)postThumbnailSavedNotificationForPath:(NSString *)thumbPath {
  dispatch_async(dispatch_get_main_queue(), ^{
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"ThumbnailSaved"
                      object:nil
                    userInfo:@{@"path" : thumbPath}];
  });
}

- (void)saveThumbnailImage:(CGImageRef)image
                  filename:(NSString *)filename
             thumbnailPath:(NSString *)thumbnailPath {

  if (!image)
    return;

  CGImageRef safeImage = CGImageCreateCopy(image);

  // Save synchronously on thumbnail queue to ensure file is written before
  // completion
  @autoreleasepool {
    if (!safeImage)
      return;

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:thumbnailPath]) {
      NSError *err = nil;
      [fm createDirectoryAtPath:thumbnailPath
          withIntermediateDirectories:YES
                           attributes:nil
                                error:&err];
      if (err) {
        NSLog(@"Failed to create thumbnail folder: %@", err);
        CGImageRelease(safeImage);
        return;
      }
    }

    NSString *thumbName = [[filename stringByDeletingPathExtension]
        stringByAppendingPathExtension:@"png"];
    NSString *thumbPath =
        [thumbnailPath stringByAppendingPathComponent:thumbName];
    NSURL *thumbURL = [NSURL fileURLWithPath:thumbPath];

    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(
        (__bridge CFURLRef)thumbURL, kUTTypePNG, 1, NULL);

    if (!destination) {
      NSLog(@"Failed to create CGImageDestination for %@", thumbName);
      CGImageRelease(safeImage);
      return;
    }

    NSDictionary *options = @{
      (__bridge id)
      kCGImageDestinationLossyCompressionQuality : @(THUMBNAIL_QUALITY_FACTOR)
    };

    CGImageDestinationAddImage(destination, safeImage,
                               (__bridge CFDictionaryRef)options);

    if (!CGImageDestinationFinalize(destination)) {
      NSLog(@"Failed to write PNG thumbnail: %@", thumbName);
    } else {
      NSLog(@"Saved PNG thumbnail: %@", thumbName);

      // Post notification that this specific thumbnail is ready
      dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"ThumbnailSaved"
                          object:nil
                        userInfo:@{@"path" : thumbPath}];
      });
    }

    CFRelease(destination);
    CGImageRelease(safeImage);
  }
}

- (void)videoQualityBadgeForURL:(NSURL *)url
                     completion:(void (^)(NSString *badge))completion {
  AVAsset *asset = [AVAsset assetWithURL:url];

  if (@available(macOS 15.0, *)) {

    [asset loadTracksWithMediaType:AVMediaTypeVideo
                 completionHandler:^(NSArray<AVAssetTrack *> *tracks,
                                     NSError *error) {
                   NSString *badge = @"";

                   if (!error && tracks.count > 0) {
                     AVAssetTrack *videoTrack = tracks.firstObject;
                     badge = [self badgeFromVideoTrack:videoTrack];
                   }
                   dispatch_async(dispatch_get_main_queue(), ^{
                     completion(badge);
                   });
                 }];

  } else {

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    AVAssetTrack *videoTrack =
        [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
#pragma clang diagnostic pop

    NSString *badge = videoTrack ? [self badgeFromVideoTrack:videoTrack] : @"";
    completion(badge);
  }
}

- (NSString *)badgeFromVideoTrack:(AVAssetTrack *)videoTrack {
  CGSize resolution = CGSizeApplyAffineTransform(videoTrack.naturalSize,
                                                 videoTrack.preferredTransform);

  resolution.width = fabs(resolution.width);
  resolution.height = fabs(resolution.height);

  if (resolution.width >= 3840 || resolution.height >= 2160)
    return @"4K";
  if (resolution.width >= 1920 || resolution.height >= 1080)
    return @"HD";
  if (resolution.width >= 1280 || resolution.height >= 720)
    return @"SD";

  return @"";
}

- (NSImage *)image:(NSImage *)image withBadge:(NSString *)badge {
  NSImage *result = [image copy];
  [result lockFocus];

  NSDictionary *attributes = @{
    NSFontAttributeName : [NSFont boldSystemFontOfSize:QUALITY_BADGE_FONT_SIZE],
    NSForegroundColorAttributeName : [NSColor whiteColor],
    NSStrokeColorAttributeName : [NSColor blackColor],
    NSStrokeWidthAttributeName : @-2
  };

  NSSize textSize = [badge sizeWithAttributes:attributes];

  CGFloat padding = 8;
  CGFloat verticalPadding = 6;
  CGFloat cornerRadius = 8;
  CGFloat marginRight = 10;
  CGFloat marginBottom = 10;

  NSColor *bgColor = [[NSColor blackColor] colorWithAlphaComponent:0.55];
  NSRect bgRect = NSMakeRect(
      result.size.width - textSize.width - padding * 2 - marginRight,
      result.size.height - textSize.height - verticalPadding * 2 - marginBottom,
      textSize.width + padding * 2, textSize.height + verticalPadding * 2);

  NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:bgRect
                                                       xRadius:cornerRadius
                                                       yRadius:cornerRadius];
  [bgColor setFill];
  [path fill];

  NSPoint textPoint = NSMakePoint(
      result.size.width - textSize.width - padding - marginRight,
      result.size.height - textSize.height - verticalPadding - marginBottom);
  [badge drawAtPoint:textPoint withAttributes:attributes];

  [result unlockFocus];
  return result;
}

- (BOOL)enableAppAsLoginItem {
  NSString *agentPath = [NSHomeDirectory()
      stringByAppendingPathComponent:
          @"Library/LaunchAgents/com.thusvill.LiveWallpaper.plist"];

  NSString *execPath = [[NSBundle mainBundle] executablePath];

  NSDictionary *plist = @{
    @"Label" : @"com.thusvill.LiveWallpaper",
    @"ProgramArguments" : @[ execPath ],
    @"RunAtLoad" : @YES,
    @"KeepAlive" : @NO
  };

  NSError *error = nil;
  NSData *plistData = [NSPropertyListSerialization
      dataWithPropertyList:plist
                    format:NSPropertyListXMLFormat_v1_0
                   options:0
                     error:&error];

  if (!plistData) {
    NSLog(@"Failed to serialize plist: %@", error);
    return NO;
  }

  if (![plistData writeToFile:agentPath atomically:YES]) {
    NSLog(@"Failed to write LaunchAgent");
    return NO;
  }

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/bin/launchctl";
  task.arguments = @[ @"load", agentPath ];
  [task launch];

  NSLog(@"Successfully registered app as login item");
  return YES;
}

- (void)startWallpaperWithPath:(NSString *)videoPath
                    onDisplays:(NSArray<NSNumber *> *)displayIDs {

  if (!videoPath || videoPath.length == 0) {
    NSLog(@"ERROR: Invalid videoPath");
    return;
  }

  self.currentVideoPath = videoPath;
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setObject:videoPath forKey:@"LastWallpaperPath"];
  [defaults synchronize];

  const char *videoPathCStr = [videoPath UTF8String];
  std::string videoPathStr(videoPathCStr);
  std::filesystem::path p(videoPathStr);
  std::string videoName = p.stem().string();

  if (!fs::exists(videoPathStr)) {
    NSLog(@"Video file does not exist: %@", videoPath);
    return;
  }

  NSString *imageFilename =
      [NSString stringWithFormat:@"%s.png", videoName.c_str()];
  NSString *imagePath = [[self staticWallpaperCachePath]
      stringByAppendingPathComponent:imageFilename];

  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:imagePath] && !_generatingImages) {
    NSLog(@"Static wallpaper not found, generating for: %@", videoPath);
    [self generateStaticWallpapersForFolder:[self getFolderPath]
                             withCompletion:nil];
  }
  NSMutableArray<NSNumber *> *screensToUse = [displayIDs mutableCopy];
  if (screensToUse.count == 0) {
    screensToUse = [NSMutableArray array];
    for (const Display &display : displays) {
      [screensToUse addObject:@(display.screen)];
    }
  }

  for (NSNumber *displayNum in screensToUse) {
    CGDirectDisplayID displayID =
        (CGDirectDisplayID)[displayNum unsignedIntValue];
    [self launchDaemonOnScreen:videoPath
                     imagePath:imagePath
                     displayID:displayID];
  }
}

- (void)applyWallpaperToDisplay:(CGDirectDisplayID)displayID
                      videoPath:(NSString *)videoPath {
  NSLog(@"Applying wallpaper to display: %u with video: %@", displayID,
        videoPath);

  [self startWallpaperWithPath:videoPath onDisplays:@[ @(displayID) ]];
}

- (void)launchDaemonOnScreen:(NSString *)videoPath
                   imagePath:(NSString *)imagePath
                   displayID:(CGDirectDisplayID)displayID {
  NSString *daemonRelativePath = @"Contents/MacOS/wallpaperdaemon";
  NSString *appPath = [[NSBundle mainBundle] bundlePath];
  NSString *daemonPath =
      [appPath stringByAppendingPathComponent:daemonRelativePath];

  float volume =
      [[NSUserDefaults standardUserDefaults] floatForKey:@"wallpapervolume"];
  NSString *volumeStr = [NSString stringWithFormat:@"%.2f", volume];
  NSString *scaleMode =
      [[NSUserDefaults standardUserDefaults] stringForKey:@"scale_mode"];

  if (!scaleMode || scaleMode.length == 0) {
    scaleMode = @"fill";
    [[NSUserDefaults standardUserDefaults] setObject:scaleMode
                                              forKey:@"scale_mode"];
    [[NSUserDefaults standardUserDefaults] synchronize];
  }

  NSLog(@"Scaling mode: %@", scaleMode);

  if (!displayID) {
    NSLog(@"Display ID not valid %u", displayID);
    displayID = [[[NSScreen mainScreen] deviceDescription][@"NSScreenNumber"]
        unsignedIntValue];
    NSLog(@"Display ID changed to %u", displayID);
  }

  NSString *display = [NSString stringWithFormat:@"%u", displayID];

  const char *daemonPathC = [daemonPath UTF8String];
  const char *args[] = {daemonPathC,
                        [videoPath UTF8String],
                        [imagePath UTF8String],
                        [volumeStr UTF8String],
                        [scaleMode UTF8String],
                        displayID ? [display UTF8String] : "",
                        NULL};

  pid_t pid;
  int status =
      posix_spawn(&pid, daemonPathC, NULL, NULL, (char *const *)args, environ);
  if (status != 0) {
    NSLog(@"Failed to launch daemon: %d", status);
  } else {
    _daemonPIDs.push_back(pid);
    NSLog(@"Launched daemon with PID: %d", pid);
  }
  SetWallpaperDisplay(pid, displayID, std::string([videoPath UTF8String]),
                      std::string([imagePath UTF8String]));
}

- (void)killAllDaemons {
  NSTask *killTask = [[NSTask alloc] init];
  killTask.launchPath = @"/usr/bin/killall";
  killTask.arguments = @[ @"wallpaperdaemon" ];
  [killTask launch];
  [killTask waitUntilExit];

  int status = killTask.terminationStatus;
  if (status != 0) {
    NSLog(@"No running wallpaperdaemon process found or killall failed");
  } else {
    NSLog(@"wallpaperdaemon processes killed");
  }

  for (pid_t pid : _daemonPIDs) {
    kill(pid, SIGTERM);
  }
  _daemonPIDs.clear();

  CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFSTR("com.live.wallpaper.terminate"), NULL, NULL, true);
}

- (void)checkFolderPath {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  if ([defaults objectForKey:@"WallpaperFolder"]) {
    folderPath = [defaults stringForKey:@"WallpaperFolder"];
  } else if (!folderPath) {
    folderPath = [NSHomeDirectory() stringByAppendingPathComponent:@"LiveWall"];
    [defaults setObject:folderPath forKey:@"WallpaperFolder"];
    [defaults synchronize];
  }
}

- (NSString *)getFolderPath {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *path = [defaults stringForKey:@"WallpaperFolder"];

  if (!path) {

    NSString *cacheDir =
        [[[NSFileManager defaultManager]
             URLsForDirectory:NSCachesDirectory
                    inDomains:NSUserDomainMask].firstObject path];

    path = [cacheDir stringByAppendingPathComponent:@"LiveWallpaper"];

    [defaults setObject:path forKey:@"WallpaperFolder"];
    [defaults synchronize];
  }

  return path;
}

- (void)checkWallpapers{
    if(_wallpaperList.count > 0){
        [_wallpaperList removeAllObjects];
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    folderPath = [self getFolderPath];
    NSArray<NSString *> *allFiles =
        [fileManager contentsOfDirectoryAtPath:folderPath error:&error];

    if (error) {
      NSLog(@"Error reading directory: %@", error.localizedDescription);
        NSLog(@"Wallaper List returns Empty");
        return;
      
    }
    
    for (NSString *fileName in allFiles) {
      NSString *fileExtension = [[fileName pathExtension] lowercaseString];

      if ([fileExtension isEqualToString:@"mp4"] ||
          [fileExtension isEqualToString:@"mov"]) {
        NSString *fullPath = [folderPath stringByAppendingPathComponent:fileName];
        [_wallpaperList addObject:fullPath];
          NSLog(@"detected %@", fullPath);
      }
    }

    if (_wallpaperList.count == 0) {
        NSLog(@"Folder is empty, return zero for playlist");
        return;
    }
    
}

-(void) nextWallpaper{
    
    if(_rotationType == 1){
        if (_wallpaperList == nil || _wallpaperList.count == 0) {
                NSLog(@"⚠️ Cannot rotate: wallpaperList is empty.");
                [self stopWallpaperRotation];
                return;
            }
        
        _currentWallpaper = (_currentWallpaper + 1) % _wallpaperList.count;
        for (Display display : displays) {

          if (!display.videoPath.empty()) {
            CGDirectDisplayID displayID = DisplayIDFromUUID(display.uuid);

            [self startWallpaperWithPath:
             _wallpaperList[_currentWallpaper]
                              onDisplays:@[ @(displayID) ]];
          }
        }
        
    }else if(_rotationType == 2){
        [self randomWallpapersLid];
    }
}
- (void)stopWallpaperRotation {
    [self.wallpaperTimer invalidate];
    self.wallpaperTimer = nil;
    NSLog(@"Wallpaper rotation stoped.");
}
- (void)startWallpaperRotation{
    int delay = _rotationDelay;
    [self stopWallpaperRotation];
    [self checkWallpapers];
    
    if (_currentWallpaper >= _wallpaperList.count) {
            _currentWallpaper = 0;
        }

    self.wallpaperTimer = [NSTimer scheduledTimerWithTimeInterval:(NSTimeInterval)delay
                                                           target:self
                                                         selector:@selector(nextWallpaper)
                                                         userInfo:nil
                                                          repeats:YES];
    
    [self.wallpaperTimer fire];
    NSLog(@"Wallpaper rotation started with %d delay.", delay);
}

- (void)scanDisplays {
  ScanDisplays();
}

- (NSArray *)getDisplays {
  NSMutableArray *result = [NSMutableArray array];

  for (const Display &d : displays) {
    DisplayObjc *obj =
        [[DisplayObjc alloc] initWithDaemon:d.daemon
                                     screen:d.screen
                                       uuid:@(d.uuid.c_str())
                                  videoPath:@(d.videoPath.c_str())
                                  framePath:@(d.framePath.c_str())];

    [result addObject:obj];
  }

  return result;
}

- (void)selectFolder:(NSString *)path {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setObject:path forKey:@"WallpaperFolder"];
}

- (void)terminateApplication {
  SaveSystem::Save(displays);
  [self killAllDaemons];
    [self removeNotifications];
}

- (BOOL)isFirstLaunch {
  NSString *const kFirstLaunchKey = @"HasLaunchedOnce";
  if (![[NSUserDefaults standardUserDefaults] boolForKey:kFirstLaunchKey]) {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kFirstLaunchKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    return YES;
  }
  return NO;
}

-(void)updateVolume:(double)value{
    float f_percentage = value;
    float volume = f_percentage / 100.0f;

      NSLog(@"Slider: %.0f%% → volume: %.2f", f_percentage, volume);


      [[NSUserDefaults standardUserDefaults] setFloat:f_percentage
                                               forKey:@"wallpapervolumeprecentage"];
      [[NSUserDefaults standardUserDefaults] setFloat:volume
                                               forKey:@"wallpapervolume"];
      [[NSUserDefaults standardUserDefaults] synchronize];

      CFNotificationCenterPostNotification(
          CFNotificationCenterGetDarwinNotifyCenter(),
          CFSTR("com.live.wallpaper.volumeChanged"), NULL, NULL, true);
    }

-(void)updateScaleMode:(NSInteger)mode{
    
    [[NSUserDefaults standardUserDefaults] setObject:@(mode)
                                               forKey:@"scale_mode"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.live.wallpaper.scaleModeChanged"), NULL, NULL, true);
}


@end

CGImageRef CompressImageWithQuality(CGImageRef image, float qualityFactor) {
  NSBitmapImageRep *bitmapRep =
      [[NSBitmapImageRep alloc] initWithCGImage:image];

  NSData *compressedData =
      [bitmapRep representationUsingType:NSBitmapImageFileTypePNG
                              properties:@{
                                NSImageCompressionFactor : @(qualityFactor)
                              }];

  NSBitmapImageRep *compressedRep =
      [NSBitmapImageRep imageRepWithData:compressedData];
  return [compressedRep CGImage];
}

