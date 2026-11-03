import Foundation
import CoreGraphics
import ThermalCore

struct ChartCoordinatesTests {
    func testSharedAxisTicks() {
        expectEqual(ChartCoordinates.ticks(in:20...130),[25,50,75,100,125])
        expectEqual(ChartCoordinates.ticks(in:0...100),[0,25,50,75,100])
        let signed=ChartCoordinates.ticks(in:(-0.25)...0.25)
        expectTrue(signed.contains(0) && signed.count==5)
        expectEqual(signed.first ?? .nan,-0.2,accuracy:0.00001)
        expectEqual(signed.last ?? .nan,0.2,accuracy:0.00001)
        expectEqual(ChartCoordinates.ticks(in:5...5),[5])
    }
    func testSignedValuesAndInspection() {
        let coordinates=ChartCoordinates(frame:CGRect(x:44,y:8,width:400,height:200),xRange:1000...1600,yRange:-5...15)
        let position=coordinates.position(x:1300,y:-2)
        expectEqual(position.x,244,accuracy:0.001)
        expectEqual(position.y,178,accuracy:0.001)
        let value=coordinates.value(at:position)
        expectEqual(value?.x ?? .nan,1300,accuracy:0.001)
        expectEqual(value?.y ?? .nan,-2,accuracy:0.001)
        expectNil(coordinates.value(at:CGPoint(x:10,y:178)))
        expectNil(coordinates.value(at:CGPoint(x:Double.nan,y:178)))
    }
    func testCurveDragClampsAtPlotEdges() {
        let coordinates=ChartCoordinates(frame:CGRect(x:44,y:8,width:400,height:200),xRange:30...100,yRange:1000...6000)
        let value=coordinates.value(at:CGPoint(x:1000,y:-300),clamped:true)
        expectEqual(value?.x ?? .nan,100,accuracy:0.001)
        expectEqual(value?.y ?? .nan,6000,accuracy:0.001)
        let low=coordinates.value(at:CGPoint(x:-20,y:500),clamped:true)
        expectEqual(low?.x ?? .nan,30,accuracy:0.001)
        expectEqual(low?.y ?? .nan,1000,accuracy:0.001)
        let empty=ChartCoordinates(frame:.zero,xRange:30...100,yRange:1000...6000)
        expectNil(empty.value(at:.zero,clamped:true))
    }
}
