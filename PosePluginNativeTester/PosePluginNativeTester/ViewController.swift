//
//  ViewController.swift
//  PosePluginNativeTester
//
//  Created by Mikko Karvonen on 4.9.2020.
//  Copyright © 2020 Mikko Karvonen. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import GLKit

struct LocalizationInfo {
    var mapHandle: Int32 = -1
    var position: float3
    var rotation: float4
}

struct LocalizerStats
{
    var localizationAttemptCount = 0;
    var localizationSuccessCount = 0;
}

func SCNMatrix4MakeWithQuaternion(q: float4) -> SCNMatrix4 {
    let m = GLKMatrix4MakeWithQuaternion(GLKQuaternionMake(q.x, q.y, q.z, q.w))
    let r = SCNMatrix4(m11: m.m00, m12: m.m01, m13: m.m02, m14: m.m03,
                       m21: m.m10, m22: m.m11, m23: m.m12, m24: m.m13,
                       m31: m.m20, m32: m.m21, m33: m.m22, m34: m.m23,
                       m41: m.m30, m42: m.m31, m43: m.m32, m44: m.m33);
    return r
}

class ViewController: UIViewController, ARSCNViewDelegate {
    let mapName = "41163-Olkkaria"  // sample map, change this to your own and add the .bytes file to the Xcode project

    var pointCloudNode: SCNNode?
    var stats = LocalizerStats.init()
    
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var locLabel: UILabel!
    @IBOutlet weak var locButton: UIButton!
    
    @IBAction func didTapLocalize(_ sender: UIButton) {
        if let frame = sceneView.session.currentFrame {
            localizeImage(frame: frame) { (locInfo) in
                self.stats.localizationAttemptCount += 1
                
                if locInfo.mapHandle >= 0 {
                    let t = SCNVector3Make(locInfo.position.x, locInfo.position.y, locInfo.position.z)
                    let r = SCNMatrix4MakeWithQuaternion(q: locInfo.rotation)

                    // fix handedness
                    // SDK v1.15+
                    let m = SCNMatrix4(m11:  r.m11, m12:  r.m12, m13:  r.m13, m14: 0.0,
                                       m21: -r.m21, m22: -r.m22, m23: -r.m23, m24: 0.0,
                                       m31: -r.m31, m32: -r.m32, m33: -r.m33, m34: 0.0,
                                       m41:    t.x, m42:    t.y, m43:    t.z, m44: 1.0)
                    
                    /* SDK v1.14
                    let m = SCNMatrix4(m11: -r.m21, m12: -r.m22, m13:  r.m23, m14: 0.0,
                                       m21:  r.m11, m22:  r.m12, m23: -r.m13, m24: 0.0,
                                       m31: -r.m31, m32: -r.m32, m33:  r.m33, m34: 0.0,
                                       m41:    t.x, m42:    t.y, m43:   -t.z, m44: 1.0)
                    */
                            
                    if let pc = self.pointCloudNode {
                        pc.transform = SCNMatrix4Mult(SCNMatrix4Invert(m), SCNMatrix4(frame.camera.transform))
                    }
                    
                    self.stats.localizationSuccessCount += 1
                }
                
                DispatchQueue.main.async {
                    self.locLabel.text = "Successful localizations: \(self.stats.localizationSuccessCount)/\(self.stats.localizationAttemptCount)"
                }
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        
        // Create a new scene
        let scene = SCNScene(named: "art.scnassets/ship.scn")!
        
        // Set the scene to the view
        sceneView.scene = scene
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()

        // Run the view's session
        sceneView.session.run(configuration)
        
        if let url = Bundle.main.url(forResource: mapName, withExtension: "bytes") {
            do {
                let data = try Data.init(contentsOf: url)
                let ptr = UnsafeMutablePointer<Int8>.allocate(capacity: data.count)
                let bytes = UnsafeMutableBufferPointer(start: ptr, count: data.count)
                let result = data.copyBytes(to: bytes)
                print("Bytes loaded: \(result)")
                let mapHandle = icvLoadMap(bytes.baseAddress!)
                
                if mapHandle >= 0 {
                    print("Map handle: \(mapHandle)")
                    let maxNumPoints = 65535
                    let pointer = UnsafeMutablePointer<Float>.allocate(capacity: 3*maxNumPoints)
                    let points = UnsafeMutableBufferPointer(start: pointer, count: 3*maxNumPoints)
                    let num = icvPointsGet(mapHandle, points.baseAddress!, Int32(maxNumPoints))
                    var p: [float3] = []
                    for i in stride(from: 0, to: Int(num), by: 3) {
                        // SDK v1.15+
                        let point = float3(points[i], points[i+1], points[i+2])
                        /* SDK v1.14
                        let point = float3(points[i], points[i+1], -points[i+2])
                        */
                        p.append(point)
                    }
                    print("How many points: \(p.count)")

                    let pcg = pointCloudGeometry(for: p)
                    pointCloudNode = SCNNode(geometry: pcg)
                    sceneView.scene.rootNode.addChildNode(pointCloudNode!)
                }
                else {
                    print("No valid map id")
                }
                
                //let r = icvFreeMap(mapId)
                //print("Freemap result: \(r)")
            } catch {
                print("No file found")
            }
        }
    }
    
    func localizeImage(frame: ARFrame, completion:@escaping (LocalizationInfo)->()) {
        let posPtr = UnsafeMutablePointer<Float>.allocate(capacity: 3)
        let pos = UnsafeMutableBufferPointer(start: posPtr, count: 3)
        let rotPtr = UnsafeMutablePointer<Float>.allocate(capacity: 4)
        let rot = UnsafeMutableBufferPointer(start: rotPtr, count: 4)
        let intrPtr = UnsafeMutablePointer<Float>.allocate(capacity: 4)
        let intrinsics = UnsafeMutableBufferPointer(start: intrPtr, count: 4)
        let handlesPtr = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        let handles = UnsafeMutableBufferPointer(start: handlesPtr, count: 1)
        let width = Int32(frame.camera.imageResolution.width)
        let height = Int32(frame.camera.imageResolution.height)
        
        var localizationInfo = LocalizationInfo.init(position: float3.init(), rotation: float4.init())
        
        intrinsics[0] = frame.camera.intrinsics.columns.0.x // fx
        intrinsics[1] = frame.camera.intrinsics.columns.1.y // fy
        intrinsics[2] = frame.camera.intrinsics.columns.2.x // ox
        intrinsics[3] = frame.camera.intrinsics.columns.2.y // oy
        
        let pixelBuffer = frame.capturedImage
        
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange else {
            NSLog("ERROR: capturedImage had an unexpected pixel format.")
            return
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        
        let rawYBuffer = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        
        let n: Int32 = 0;
        
        DispatchQueue.global(qos: .userInitiated).async {
            let r = icvLocalize(pos.baseAddress!, rot.baseAddress!, n, handles.baseAddress!, width, height, intrinsics.baseAddress!, rawYBuffer, 0, 12, 0, 2.0, 1)
            
            if (r >= 0) {
                localizationInfo.mapHandle = r
                localizationInfo.position = float3(pos[0], pos[1], pos[2])
                localizationInfo.rotation = float4(rot[0], rot[1], rot[2], rot[3])
                print("Localized, map handle: \(r)")
                print("Pos x: \(pos[0]) y: \(pos[1]) z: \(pos[2])")
                print("Rot x: \(rot[0]) y: \(rot[1]) z: \(rot[2]) w: \(rot[3])")
            }
            
            completion(localizationInfo)
        }
    }

    func pointCloudGeometry(for points:[float3]) -> SCNGeometry? {
        guard !points.isEmpty else { return nil }
                
        let stride = MemoryLayout<float3>.size
        let pointData = Data(bytes: points, count: stride * points.count)
        
        let source = SCNGeometrySource(data: pointData,
                                       semantic: SCNGeometrySource.Semantic.vertex,
                                       vectorCount: points.count,
                                       usesFloatComponents: true,
                                       componentsPerVector: 3,
                                       bytesPerComponent: MemoryLayout<Float>.size,
                                       dataOffset: 0,
                                       dataStride: stride)
        
        let pointSize:CGFloat = 10
        let element = SCNGeometryElement(data: nil, primitiveType: .point, primitiveCount: points.count, bytesPerIndex: 0)
        element.pointSize = 0.001
        element.minimumPointScreenSpaceRadius = pointSize
        element.maximumPointScreenSpaceRadius = pointSize
        
        let pointsGeometry = SCNGeometry(sources: [source], elements: [element])
        
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.red
        material.isDoubleSided = true
        material.locksAmbientWithDiffuse = true
        
        return pointsGeometry
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }

    // MARK: - ARSCNViewDelegate
    
/*
    // Override to create and configure nodes for anchors added to the view's session.
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        let node = SCNNode()
     
        return node
    }
*/
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
}
