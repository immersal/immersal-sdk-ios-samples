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
import simd

struct LocalizerStats
{
    var localizationAttemptCount = 0;
    var localizationSuccessCount = 0;
}

class ViewController: UIViewController, ARSCNViewDelegate {
    let mapName = "100879-InsideMapTest"  // sample map, change this to your own and add the .bytes file to the Xcode project
    let mapID = 100879	// change this to your map ID
    let token = "IMMERSAL_DEVELOPER_TOKEN"	// change this to your dev token

    var pointCloudNode: SCNNode?
    var mapHandle: Int32 = -1
    var stats = LocalizerStats.init()
    var mapToEcef: [Double]?
    
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var locLabel: UILabel!
    @IBOutlet weak var locButton: UIButton!
    
    @IBAction func didTapLocalize(_ sender: UIButton) {
        if let frame = sceneView.session.currentFrame {
            localizeImage(frame: frame) { (locInfo) in
                self.didLocalize(frame: frame, locInfo: locInfo)
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
        
        fetchMapToEcef(mapID: mapID, token: token) { ecefCoordinates in
            if let coordinates = ecefCoordinates {
                self.mapToEcef = coordinates
            } else {
                print("Failed to retrieve ECEF coordinates")
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()

        // Run the view's session
        sceneView.session.run(configuration)
        
        mapHandle = loadMap(name: mapName)
        print("Map handle: \(mapHandle)")
        
        if mapHandle >= 0 {
            let maxNumPoints = icvPointsGetCount(mapHandle)
            var points = [Float](repeating: 0, count: 3 * Int(maxNumPoints))
            let num = icvPointsGet(mapHandle, &points, maxNumPoints)
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
    }
    
    func loadMap(name: String) -> Int32 {
        var r: Int32 = -1
        if let url = Bundle.main.url(forResource: name, withExtension: "bytes") {
            do {
                let data = try Data.init(contentsOf: url)
                let ptr = UnsafeMutablePointer<Int8>.allocate(capacity: data.count)
                let bytes = UnsafeMutableBufferPointer(start: ptr, count: data.count)
                let result = data.copyBytes(to: bytes)
                print("Bytes loaded: \(result)")
                r = icvLoadMap(bytes.baseAddress!)
                ptr.deallocate()

                if r >= 0 {
                    print("Map loaded")
                }
                else {
                    print("No valid map id")
                }
            } catch {
                print("No file found")
            }
        }
        return r
    }
    
    func freeMap(handle: Int32) -> Int32 {
        return icvFreeMap(handle)
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
        let channels = Int32(1)
        let solverType = Int32(0)
        
        var localizeInfo = LocalizeInfo.init()
        
        intrinsics[0] = frame.camera.intrinsics.columns.0.x // fx
        intrinsics[1] = frame.camera.intrinsics.columns.1.y // fy
        intrinsics[2] = frame.camera.intrinsics.columns.2.x // ox
        intrinsics[3] = frame.camera.intrinsics.columns.2.y // oy
        
        print("width: \(width) height: \(height)")
        print("intrinsics: \(Array(intrinsics))")
        
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
            localizeInfo = icvLocalize(n, handles.baseAddress!, width, height, intrinsics.baseAddress!, rawYBuffer, channels, solverType, rot.baseAddress!)
            
            rotPtr.deallocate()
            intrPtr.deallocate()
            handlesPtr.deallocate()
            
            completion(localizeInfo)
        }
    }
    
    func didLocalize(frame: ARFrame, locInfo: LocalizeInfo) {
        self.stats.localizationAttemptCount += 1
        
        print("handle: \(locInfo.handle)")
        
        if locInfo.handle >= 0 {
            let t = SCNVector3Make(locInfo.position.x, locInfo.position.y, locInfo.position.z)
            let q = simd_quaternion(locInfo.rotation.x, locInfo.rotation.y, locInfo.rotation.z, locInfo.rotation.w)
            let r = SCNMatrix4.init(simd_matrix4x4(q))
            let m = SCNMatrix4(m11:  r.m11, m12:  r.m12, m13:  r.m13, m14: r.m14,
                               m21: -r.m21, m22: -r.m22, m23: -r.m23, m24: r.m24,
                               m31: -r.m31, m32: -r.m32, m33: -r.m33, m34: r.m34,
                               m41:    t.x, m42:    t.y, m43:    t.z, m44: r.m44)
            
            print("Localized, map handle: \(locInfo.handle)")
            print("Pos x: \(locInfo.position.x) y: \(locInfo.position.y) z: \(locInfo.position.z)")
            print("Rot x: \(locInfo.rotation.x) y: \(locInfo.rotation.y) z: \(locInfo.rotation.z) w: \(locInfo.rotation.w)\n")
            
            let pose: SCNMatrix4 = SCNMatrix4Mult(SCNMatrix4Invert(m), SCNMatrix4(frame.camera.transform))

            if let pc = self.pointCloudNode {
                pc.transform = pose
            }
            
            if let m2e = self.mapToEcef {
                let mapToEcefPtr = UnsafeMutablePointer<Double>.allocate(capacity: m2e.count)
                mapToEcefPtr.initialize(from: m2e, count: m2e.count)
                let posPtr = UnsafeMutablePointer<Float>.allocate(capacity: 3)
                posPtr.initialize(from: [locInfo.position.x, locInfo.position.y, locInfo.position.z], count: 3)
                let rotPtr = UnsafeMutablePointer<Float>.allocate(capacity: 4)
                rotPtr.initialize(from: [locInfo.rotation.x, locInfo.rotation.y, locInfo.rotation.z, locInfo.rotation.w], count: 4)
                
                var ecefPos = [Double](repeating: 0, count: 3)
                var ret = icvPosMapToEcef(&ecefPos, posPtr, mapToEcefPtr)
                print("icvPosMapToEcef: \(ret)")
                print("pos ecef: \(ecefPos)\n")
                
                var wgs84 = [Double](repeating: 0, count: 3)
                ret = icvPosEcefToWgs84(&wgs84, &ecefPos)
                print("icvPosEcefToWgs84: \(ret)")
                print("pos wgs84: \(wgs84)\n")

                var mapPos = [Float](repeating: 0, count: 3)
                ret = icvPosEcefToMap(&mapPos, &ecefPos, mapToEcefPtr)
                print("icvPosEcefToMap: \(ret)")
                print("pos map: \(mapPos)\n")

                var ecefRot = [Float](repeating: 0, count: 4)
                ret = icvRotMapToEcef(&ecefRot, rotPtr, mapToEcefPtr);
                print("icvRotMapToEcef: \(ret)")
                print("rot ecef: \(ecefRot)\n")

                var mapRot = [Float](repeating: 0, count: 4)
                ret = icvRotEcefToMap(&mapRot, &ecefRot, mapToEcefPtr)
                print("icvRotEcefToMap: \(ret)")
                print("rot map: \(mapRot)\n")
                
                ret = icvPosWgs84ToEcef(&ecefPos, &wgs84);
                print("icvPosWgs84ToEcef: \(ret)")
                print("pos ecef: \(ecefPos)\n")
                
                let cd = compassDir(cam: frame.camera, trackerToMap: SCNMatrix4Invert(pose), mapToEcef: m2e)
                var heading = atan2(-cd.x, cd.y) * (180.0 / .pi)
                if heading < 0 {
                    heading = 360.0 - abs(heading)
                }
                print("heading: \(heading)")

                mapToEcefPtr.deallocate()
                posPtr.deallocate()
                rotPtr.deallocate()
            }
            
            self.stats.localizationSuccessCount += 1
        }
        
        DispatchQueue.main.async {
            self.locLabel.text = "Successful localizations: \(self.stats.localizationSuccessCount)/\(self.stats.localizationAttemptCount)"
        }
    }
    
    func fetchMapToEcef(mapID: Int, token: String, completion: @escaping ([Double]?) -> Void) {
        let url = URL(string: "https://api.immersal.com/ecef")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let payload: [String: Any] = [
            "id": mapID,
            "token": token
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
            request.httpBody = jsonData
        } catch {
            print("Failed to serialize JSON: \(error.localizedDescription)")
            completion(nil)
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil else {
                print("Failed to fetch data: \(error!.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                if let data = data,
                   let errorResponse = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    print("Error:", errorResponse)
                } else {
                    print("Failed to fetch data with status code:", (response as? HTTPURLResponse)?.statusCode ?? "Unknown")
                }
                completion(nil)
                return
            }
            
            guard let data = data else {
                print("No data received.")
                completion(nil)
                return
            }
            
            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let ecefCoordinates = jsonResponse["ecef"] as? [Double] {
                    print("Map ECEF coordinates:", ecefCoordinates)
                    completion(ecefCoordinates)
                } else {
                    print("Map ECEF coordinates not found in the response")
                    completion(nil)
                }
            } catch {
                print("Failed to parse JSON: \(error.localizedDescription)")
                completion(nil)
            }
        }
        task.resume()
    }

    func pointCloudGeometry(for points:[SIMD3<Float>]) -> SCNGeometry? {
        guard !points.isEmpty else { return nil }
                
        let vertices = points.map { (point) -> SCNVector3 in
            return SCNVector3(point)
        }
        
        let source = SCNGeometrySource(vertices: vertices)
        
        /*
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
         */
        
        let pointSize:CGFloat = 1.0
        let element = SCNGeometryElement(data: nil, primitiveType: .point, primitiveCount: vertices.count, bytesPerIndex: MemoryLayout<Int>.size)
        element.pointSize = pointSize
        element.minimumPointScreenSpaceRadius = pointSize
        element.maximumPointScreenSpaceRadius = 20.0
        
        let pointsGeometry = SCNGeometry(sources: [source], elements: [element])
        
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.red
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.locksAmbientWithDiffuse = true
        
        pointsGeometry.firstMaterial = material;
        
        return pointsGeometry
    }
        
    func compassDir(cam: ARCamera, trackerToMap: SCNMatrix4, mapToEcef: [Double]) -> SIMD2<Float> {
        // Helper functions
        func multiplyPoint(_ matrix: matrix_float4x4, _ point: SIMD3<Float>) -> SIMD3<Float> {
            let vec = SIMD4<Float>(point.x, point.y, point.z, 1.0)
            let transformedVec = matrix * vec
            return SIMD3<Float>(transformedVec.x, transformedVec.y, transformedVec.z)
        }

        func rotZ(_ angle: Double) -> matrix_float4x4 {
            let rad = Float(angle * .pi / 180.0)
            let c = cos(rad)
            let s = sin(rad)
            
            return matrix_float4x4(
                SIMD4<Float>(c, -s, 0, 0),
                SIMD4<Float>(s, c, 0, 0),
                SIMD4<Float>(0, 0, 1, 0),
                SIMD4<Float>(0, 0, 0, 1)
            )
        }

        func rotX(_ angle: Double) -> matrix_float4x4 {
            let rad = Float(angle * .pi / 180.0)
            let c = cos(rad)
            let s = sin(rad)
            
            return matrix_float4x4(
                 SIMD4<Float>(1, 0, 0, 0),
                 SIMD4<Float>(0, c, -s, 0),
                 SIMD4<Float>(0, s, c, 0),
                 SIMD4<Float>(0, 0, 0, 1)
            )
        }

        func rot3d(lat: Double, lon: Double) -> matrix_float4x4 {
            let rz = rotZ(90 + lon)
            let rx = rotX(90 - lat)
            return rx * rz
        }
        
        let mapToEcefPtr = UnsafeMutablePointer<Double>.allocate(capacity: mapToEcef.count)
        mapToEcefPtr.initialize(from: mapToEcef, count: mapToEcef.count)
        
        let position = SIMD3<Float>(cam.transform[3].x, cam.transform[3].y, cam.transform[3].z)
        let forward = SIMD3<Float>(-cam.transform[2].x, -cam.transform[2].y, -cam.transform[2].z)

        let a = multiplyPoint(matrix_float4x4(trackerToMap), position)
        let b = multiplyPoint(matrix_float4x4(trackerToMap), position + forward)
        var A: [Float] = [a.x, a.y, a.z]
        var B: [Float] = [b.x, b.y, b.z]

        var aEcef = [Double](repeating: 0, count: 3)
        let ra = icvPosMapToEcef(&aEcef, &A, mapToEcefPtr)
        print("icvPosMapToEcef: \(ra)")
        print("aEcef: \(Array(aEcef))\n")
        var bEcef = [Double](repeating: 0, count: 3)
        let rb = icvPosMapToEcef(&bEcef, &B, mapToEcefPtr)
        print("icvPosMapToEcef: \(rb)")
        print("bEcef: \(Array(bEcef))\n")

        var wgs84 = [Double](repeating: 0, count: 3)
        let rw = icvPosEcefToWgs84(&wgs84, &aEcef)
        print("icvPosEcefToWgs84: \(rw)")
        print("wgs84: \(Array(wgs84))\n")
        let R = rot3d(lat: wgs84[0], lon: wgs84[1])
        print("R: \(R)")

        let v = SIMD3<Float>(Float(bEcef[0] - aEcef[0]), Float(bEcef[1] - aEcef[1]), Float(bEcef[2] - aEcef[2]))
        print("v: \(v)")
        let vt = R * SIMD4<Float>(simd_normalize(v), 0)
        print("vt: \(vt)")

        let d = SIMD2<Float>(vt.x, vt.y)
        print("d: \(d)")

        mapToEcefPtr.deallocate()
        
        return simd_normalize(d)
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
