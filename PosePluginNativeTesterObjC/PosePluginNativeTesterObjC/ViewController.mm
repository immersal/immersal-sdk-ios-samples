//
//  ViewController.m
//  PosePluginNativeTesterObjC
//
//  Created by Mikko Karvonen on 14.9.2022.
//

#import "ViewController.h"
#import "PosePlugin.h"
#include <vector>

@interface ViewController () <ARSCNViewDelegate>

@property (nonatomic, strong) IBOutlet ARSCNView *sceneView;
@property (nonatomic, strong) IBOutlet UILabel *locLabel;
@property (nonatomic, strong) IBOutlet UIButton *locButton;

struct point {
    float x = 0;
    float y = 0;
    float z = 0;
};

struct rotation_ {
    float x = 0;
    float y = 0;
    float z = 0;
    float w = 0;
};

struct LocalizationInfo {
    int mapHandle = -1;
    point position;
    rotation_ rotation;
};

struct LocalizerStats {
    int localizationAttemptCount = 0;
    int localizationSuccessCount = 0;
};

typedef void (^ResultBlock)(LocalizationInfo);

@end

@implementation ViewController {
    NSString* mapName;
    SCNNode* pointCloudNode;
    std::vector<point> p3;
    LocalizerStats stats;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Set the view's delegate
    self.sceneView.delegate = self;
    
    // Show statistics such as fps and timing information
    self.sceneView.showsStatistics = YES;
    
    // Create a new scene
    SCNScene *scene = [SCNScene sceneNamed:@"art.scnassets/ship.scn"];
    
    // Set the scene to the view
    self.sceneView.scene = scene;
    
    // sample map, change this to your own and add the .bytes file to the Xcode project
    
    mapName = @"67461-Taulu";
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Create a session configuration
    ARWorldTrackingConfiguration *configuration = [ARWorldTrackingConfiguration new];
    
    // Run the view's session
    [self.sceneView.session runWithConfiguration:configuration];
    
    NSURL *url = [[NSBundle mainBundle] URLForResource:mapName withExtension:@"bytes"];
    if (url != NULL) {
        NSData* data = [NSData dataWithContentsOfURL:url];
        NSLog(@"Bytes loaded: %lu", (unsigned long)data.length);
        const char *buffer = (const char*)data.bytes;
        int mapHandle = icvLoadMap(buffer);

        if (mapHandle >= 0) {
            NSLog(@"Map handle: %d", mapHandle);
            int maxNumPoints = 65535;
            std::vector<float> points (3 * maxNumPoints);
            int num = icvPointsGet(mapHandle, &points[0], maxNumPoints);
            
            for (int i = 0; i < num;)
            {
                point p;
                p.x = points[i];
                p.y = points[i+1];
                p.z = points[i+2];
                p3.push_back(p);
                i = i+3;
            }
            NSLog(@"How many points: %lu", p3.size());
            
            SCNGeometry *pcg = [self pointCloudGeometry];
            pointCloudNode = [SCNNode nodeWithGeometry:pcg];
            [self.sceneView.scene.rootNode addChildNode:pointCloudNode];
        }
        else {
            NSLog(@"No valid map id");
        }
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // Pause the view's session
    [self.sceneView.session pause];
}

- (IBAction)didTapLocalize:(id)sender {
    ARFrame* frame = self.sceneView.session.currentFrame;
    
    if (frame != NULL) {
        dispatch_queue_t localizationQueue = dispatch_queue_create("com.immersal.LocalizationQueue", NULL);
        dispatch_async(localizationQueue, ^{
            [self localizeImage:frame withCompletion:^(LocalizationInfo locInfo) {
                self->stats.localizationAttemptCount += 1;
                
                if (locInfo.mapHandle >= 0) {
                    SCNVector3 t = SCNVector3Make(locInfo.position.x, locInfo.position.y, locInfo.position.z);
                    SCNMatrix4 r = [self makeWithQuaternion:locInfo.rotation];
                    SCNMatrix4 m = { r.m11, r.m12, r.m13, 0.0,
                                    -r.m21, -r.m22, -r.m23, 0.0,
                                    -r.m31, -r.m32, -r.m33, 0.0,
                                    t.x, t.y, t.z, 1.0 };
                    
                    if (self->pointCloudNode != NULL) {
                        self->pointCloudNode.transform = SCNMatrix4Mult(SCNMatrix4Invert(m), SCNMatrix4FromMat4(frame.camera.transform));
                    }
                    
                    self->stats.localizationSuccessCount += 1;
                }
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.locLabel.text = [NSString stringWithFormat:@"Successful localizations: %d/%d", self->stats.localizationSuccessCount, self->stats.localizationAttemptCount];
                });
            }];
        });
    }
}

- (void)localizeImage:(ARFrame *)frame withCompletion:(ResultBlock)block {
    CVPixelBufferRef pixelBuffer  = frame.capturedImage;
    if (CVPixelBufferGetPixelFormatType(pixelBuffer) != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
        NSLog(@"ERROR: capturedImage had an unexpected pixel format.");
        return;
    }
    
    LocalizationInfo locInfo;

    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    void *baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    GLsizei imageWidth = (GLsizei)CVPixelBufferGetWidthOfPlane(pixelBuffer, 0);
    GLsizei imageHeight = (GLsizei)CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);

    float pos[3];
    float rot[4];
    int n = 0;
    int handles[1];
    float intrinsics[4];
    intrinsics[0] = frame.camera.intrinsics.columns[0].x;   // fx
    intrinsics[1] = frame.camera.intrinsics.columns[1].y;   // fy
    intrinsics[2] = frame.camera.intrinsics.columns[2].x;   // ox
    intrinsics[3] = frame.camera.intrinsics.columns[2].y;   // oy

    NSLog(@"Image width: %d", imageWidth);
    NSLog(@"Image height: %d", imageHeight);
    
    int r = icvLocalize(&pos[0], &rot[0], n, &handles[0], imageWidth, imageHeight, &intrinsics[0], baseAddress, 0, 12, 0, 2.0, 1);
    
    if (r >= 0) {
        locInfo.mapHandle = r;
        locInfo.position.x = pos[0];
        locInfo.position.y = pos[1];
        locInfo.position.z = pos[2];
        locInfo.rotation.x = rot[0];
        locInfo.rotation.y = rot[1];
        locInfo.rotation.z = rot[2];
        locInfo.rotation.w = rot[3];
        NSLog(@"Localized, map handle: %d", r);
        NSLog(@"Pos x: %f y: %f z: %f", pos[0], pos[1], pos[2]);
        NSLog(@"Rot x: %f y: %f z: %f w: %f", rot[0], rot[2], rot[3], rot[3]);
    }
        
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

    block(locInfo);
}

- (SCNGeometry*)pointCloudGeometry {
    if (self->p3.empty()) return NULL;
    
    NSInteger stride = sizeof(point);
    NSData *pointData = [NSData dataWithBytes:p3.data() length:p3.size() * stride];
    SCNGeometrySource *source = [SCNGeometrySource geometrySourceWithData:pointData semantic:SCNGeometrySourceSemanticVertex vectorCount:p3.size() floatComponents:YES componentsPerVector:3 bytesPerComponent:sizeof(float) dataOffset:0 dataStride:stride];
    
    CGFloat pointSize = 10;
    SCNGeometryElement *element = [SCNGeometryElement geometryElementWithData:NULL primitiveType:SCNGeometryPrimitiveTypePoint primitiveCount:p3.size() bytesPerIndex:0];
    element.pointSize = pointSize;
    element.minimumPointScreenSpaceRadius = pointSize;
    element.maximumPointScreenSpaceRadius = 20;
    
    SCNGeometry *pointsGeometry = [SCNGeometry geometryWithSources:@[source] elements:@[element]];
    
    SCNMaterial *material = [SCNMaterial material];
    material.diffuse.contents = [UIColor redColor];
    material.locksAmbientWithDiffuse = YES;
    
    pointsGeometry.firstMaterial = material;
    pointsGeometry.firstMaterial.doubleSided = YES;

    return pointsGeometry;
}

- (SCNMatrix4)makeWithQuaternion:(rotation_)q {
    GLKMatrix4 m = GLKMatrix4MakeWithQuaternion(GLKQuaternionMake(q.x, q.y, q.z, q.w));
    SCNMatrix4 r = SCNMatrix4FromGLKMatrix4(m);
    return r;
}

#pragma mark - ARSCNViewDelegate

/*
// Override to create and configure nodes for anchors added to the view's session.
- (SCNNode *)renderer:(id<SCNSceneRenderer>)renderer nodeForAnchor:(ARAnchor *)anchor {
    SCNNode *node = [SCNNode new];
 
    // Add geometry to the node...
 
    return node;
}
*/

- (void)session:(ARSession *)session didFailWithError:(NSError *)error {
    // Present an error message to the user
    
}

- (void)sessionWasInterrupted:(ARSession *)session {
    // Inform the user that the session has been interrupted, for example, by presenting an overlay
    
}

- (void)sessionInterruptionEnded:(ARSession *)session {
    // Reset tracking and/or remove existing anchors if consistent tracking is required
    
}

@end
