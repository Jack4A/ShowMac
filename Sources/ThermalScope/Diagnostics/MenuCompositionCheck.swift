import AppKit
import ThermalCore

/// Exercises migration, independently editable duplicates and native drop commands without saved writes.
@MainActor enum MenuCompositionCheck {
    static func run() {
        guard CommandLine.arguments.contains("--ui-check") else{print("Use --menu-composition-check --ui-check.");exit(2)}
        _=NSApplication.shared
        do {
            func require(_ condition:Bool,_ message:String)throws {if !condition {throw ScopeError.message(message)}}
            func preferences()->NSDictionary {NSDictionary(dictionary:UserDefaults.standard.persistentDomain(forName:Bundle.main.bundleIdentifier ?? "local.jack.ThermalScope") ?? [:])}
            let before=preferences(),model=AppModel()
            defer {model.shutdown()}
            model.menuComposition=nil;model.menuStyle="custom";model.menuItems=[.temperature,.cpu,.fan]
            model.menuTileStyles=["temperature":"stacked","cpu":"historyValue","fan":"iconValue"]
            model.menuTileLabels=["cpu":"CORE"];model.menuTileColors=["cpu":"2468AC"];model.menuTileIcons=["cpu":"sf:cpu"]
            let legacy=model.effectiveMenuComponents
            try require(legacy[0].style == .iconValue,"Legacy two-line display was not converted to horizontal display")
            try require(legacy.map(\.metric)==[.temperature,.cpu,.fan] && legacy[1].label=="CORE" && legacy[1].icon=="sf:cpu" && legacy[1].colorHex=="2468AC","Legacy settings were not preserved")
            try require(legacy.map(\.id)==model.effectiveMenuComponents.map(\.id) && model.menuComposition==nil,"Opening a legacy layout changed its identity or storage")
            try require(model.applyMenuDrop([MenuComponentDrag.template(.cpu,.icon).token],before:nil),"Template drop failed")
            let iconID=model.effectiveMenuComponents.last!.id
            try require(model.applyMenuDrop([MenuComponentDrag.template(.cpu,.bars).token],before:nil),"Duplicate metric was rejected")
            let barsID=model.effectiveMenuComponents.last!.id
            model.updateMenuComponent(id:iconID){$0.label="ICON";$0.colorHex="ABCDEF"}
            try require(model.effectiveMenuComponents.first{$0.id==barsID}?.label==nil && model.effectiveMenuComponents.first{$0.id==legacy[1].id}?.label=="CORE","Editing a duplicate changed another instance")
            try require(model.applyMenuDrop([MenuComponentDrag.existing(barsID).token],before:legacy[0].id),"Reordering failed")
            try require(model.effectiveMenuComponents.map(\.id)==[barsID]+legacy.map(\.id)+[iconID],"Reordering changed unrelated order")
            let unchanged=model.effectiveMenuComponents
            try require(!model.applyMenuDrop(["external text"],before:nil),"Foreign payload accepted")
            try require(!model.applyMenuDrop([MenuComponentDrag.existing("missing").token],before:nil),"Stale item accepted")
            try require(!model.applyMenuDrop([MenuComponentDrag.existing(iconID).token,"another"],before:nil),"Multiple payloads accepted")
            try require(!model.applyMenuDrop([MenuComponentDrag.template(.cpu,.value).token],before:"missing"),"Stale destination accepted")
            try require(model.effectiveMenuComponents==unchanged,"Rejected drop changed the layout")
            model.setMenuComponentIcon("none",id:iconID)
            try require(model.effectiveMenuComponents.first{$0.id==iconID}?.style == .value,"Hiding an icon left an empty item")
            let encoded=try JSONEncoder().encode(model.effectiveMenuComponents)
            try require(MenuBarComponent.decode(encoded)==model.effectiveMenuComponents,"Component settings did not round-trip")
            let tiles=MenuBarAppearanceRenderer.tiles(model:model)
            try require(tiles.count==5 && tiles.map(\.metric)==model.effectiveMenuComponents.map(\.metric),"Renderer omitted or regrouped duplicate components")
            let rendered=MenuBarAppearanceRenderer.image(tiles:tiles,ending:model.metricHistory.end,spacing:4,graphWidth:44,background:false)
            try require(rendered.size.width>100 && rendered.size.height==22,"Composed menu did not render")
            while model.effectiveMenuComponents.count>1 {try require(model.removeMenuComponent(id:model.effectiveMenuComponents[0].id),"Remove failed")}
            try require(!model.removeMenuComponent(id:model.effectiveMenuComponents[0].id),"Last item was removed")
            while model.effectiveMenuComponents.count<MenuBarComponent.limit {try require(model.insertMenuComponent(metric:.cpu,style:.value),"Insert below limit failed")}
            try require(!model.insertMenuComponent(metric:.cpu,style:.value),"Component bound was ignored")
            var bad=legacy;bad[1].id=bad[0].id
            try require(MenuBarComponent.decode(try JSONEncoder().encode(bad))==nil && MenuBarComponent.decode(Data("bad".utf8))==nil && MenuBarComponent.decode(Data("[]".utf8))==nil,"Invalid storage was accepted")
            model.applyMenuPreset(0)
            try require(model.menuComposition==nil && model.effectiveMenuComponents.map(\.metric)==[.temperature,.cpu],"Preset did not replace the composition")
            try require(MenuBarAppearanceRenderer.tiles(model:model).allSatisfy{$0.color==nil},"Default components did not remain automatic black and white")
            let first=MenuBarComponent(metric:.cpu,style:.value),second=MenuBarComponent(metric:.cpu,style:.value)
            model.menuComposition=[first,second]
            model.updateMenuComponent(id:first.id){$0.colorHex="2468AC"}
            let colored=MenuBarAppearanceRenderer.tiles(model:model)
            try require(colored[0].color != nil && colored[1].color==nil && model.effectiveMenuComponents[1]==second,"Component color leaked to an unedited duplicate")
            for dark in [false,true] {
                let fixtures=colored.map{MenuBarTile(metric:.cpu,style:.value,label:"CPU",value:"50%",number:50,points:[],upper:100,color:$0.color)}
                let image=MenuBarAppearanceRenderer.image(tiles:fixtures,ending:Date(),spacing:4,graphWidth:44,background:false,appearance:NSAppearance(named:dark ? .darkAqua:.aqua),warningsEnabled:false)
                guard !image.isTemplate,let data=image.tiffRepresentation,let pixels=NSBitmapImageRep(data:data) else{throw ScopeError.message("Mixed automatic/custom components did not render")}
                var firstBlue=0,secondBlue=0,secondNeutral=0
                for y in 0..<pixels.pixelsHigh {for x in 0..<pixels.pixelsWide {
                    guard let c=pixels.colorAt(x:x,y:y)?.usingColorSpace(.sRGB),c.alphaComponent>0.75 else{continue}
                    let blue=c.blueComponent>c.redComponent+0.2 && c.blueComponent>c.greenComponent+0.1
                    if x<pixels.pixelsWide/2 {if blue {firstBlue+=1}}
                    else {
                        if blue {secondBlue+=1}
                        if abs(c.redComponent-c.greenComponent)<0.02 && abs(c.greenComponent-c.blueComponent)<0.02 && (dark ? c.redComponent>0.9:c.redComponent<0.1) {secondNeutral+=1}
                    }
                }}
                try require(firstBlue>0 && secondBlue==0 && secondNeutral>0,"Value-only custom color changed the neighboring black/white component")
            }
            model.updateMenuComponent(id:first.id){$0.colorHex=nil}
            let reset=MenuBarAppearanceRenderer.image(tiles:MenuBarAppearanceRenderer.tiles(model:model),ending:Date(),spacing:4,graphWidth:44,background:false,warningsEnabled:false)
            try require(model.effectiveMenuComponents==[first,second] && reset.isTemplate,"Restoring black/white did not clear only the selected color")
            model.theme=model.theme=="dark" ? "light":"dark"
            try require(before.isEqual(preferences()),"Isolated composition/theme checks changed saved preferences")
            print("PASS: legacy migration, duplicate metrics, independent edits/colors, light/dark mixed color pixels, black/white reset, drag insertion/reorder, rejected drops, round-trip, rendering, removal/limits, presets and isolated theme/menu preferences. No hardware writes.")
        } catch {print("FAIL: "+error.localizedDescription);exit(1)}
    }
}
