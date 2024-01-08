//
//  ViewController.swift
//  PosePluginNativeTester
//
//  Created by Mikko Karvonen on 4.9.2020.
//  Copyright (C) 2024 Immersal - Part of Hexagon. All Rights Reserved.
//

import UIKit
import SceneKit
import ARKit

struct LocalizerStats
{
    var localizationAttemptCount = 0;
    var localizationSuccessCount = 0;
}

class ViewController: UIViewController, ARSCNViewDelegate {
    let mapName = "92528-Test"  // sample map, change this to your own and add the .bytes file to the Xcode project

    var pointCloudNode: SCNNode?
    var stats = LocalizerStats.init()
    
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var locLabel: UILabel!
    @IBOutlet weak var locButton: UIButton!
    
    @IBAction func didTapLocalize(_ sender: UIButton) {
        if let frame = sceneView.session.currentFrame {
            localizeImage(frame: frame) { (locInfo) in
                self.stats.localizationAttemptCount += 1
                
                if locInfo.handle >= 0 {
                    let t = SCNVector3Make(locInfo.px, locInfo.py, locInfo.pz)
                    let m = SCNMatrix4(m11:  locInfo.r00, m12:  locInfo.r10, m13:  locInfo.r20, m14: 0.0,
                                       m21: -locInfo.r01, m22: -locInfo.r11, m23: -locInfo.r21, m24: 0.0,
                                       m31: -locInfo.r02, m32: -locInfo.r12, m33: -locInfo.r22, m34: 0.0,
                                       m41:    t.x, m42:    t.y, m43:    t.z, m44: 1.0)
                            
                    print("Localized, map handle: \(locInfo.handle)")
                    print("Pos x: \(t.x) y: \(t.y) z: \(t.z)")
                    
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
                    var p: [SIMD3<Float>] = []
                    for i in stride(from: 0, to: Int(num), by: 3) {
                        let point = SIMD3<Float>(points[i], points[i+1], points[i+2])
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
    
    func localizeImage(frame: ARFrame, completion:@escaping (LocalizeInfo)->()) {
        let rotPtr = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        let rot = UnsafeMutableBufferPointer(start: rotPtr, count: 1)
        let intrPtr = UnsafeMutablePointer<Float>.allocate(capacity: 4)
        let intrinsics = UnsafeMutableBufferPointer(start: intrPtr, count: 4)
        let handlesPtr = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        let handles = UnsafeMutableBufferPointer(start: handlesPtr, count: 1)
        let width = Int32(frame.camera.imageResolution.width)
        let height = Int32(frame.camera.imageResolution.height)
        
        var localizeInfo = LocalizeInfo.init()
        
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
            localizeInfo = icvLocalize(n, handles.baseAddress!, width, height, intrinsics.baseAddress!, rawYBuffer, 0, rot.baseAddress!)
            
            completion(localizeInfo)
        }
    }

    func pointCloudGeometry(for points:[SIMD3<Float>]) -> SCNGeometry? {
        guard !points.isEmpty else { return nil }
                
        let stride = MemoryLayout<SIMD3<Float>>.size
        let pointData = Data(bytes: points, count: stride * points.count)
        
        let source = SCNGeometrySource(data: pointData,
                                       semantic: SCNGeometrySource.Semantic.vertex,
                                       vectorCount: points.count,
                                       usesFloatComponents: true,
                                       componentsPerVector: 3,
                                       bytesPerComponent: MemoryLayout<Float>.size,
                                       dataOffset: 0,
                                       dataStride: stride)
        
        let pointSize:CGFloat = 10;
        let element = SCNGeometryElement(data: nil, primitiveType: .point, primitiveCount: points.count, bytesPerIndex: 0)
        element.pointSize = pointSize;
        element.minimumPointScreenSpaceRadius = pointSize
        element.maximumPointScreenSpaceRadius = 20
        
        let pointsGeometry = SCNGeometry(sources: [source], elements: [element])
        
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.red
        material.isDoubleSided = true
        material.locksAmbientWithDiffuse = true
        
        pointsGeometry.firstMaterial = material;
        
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
