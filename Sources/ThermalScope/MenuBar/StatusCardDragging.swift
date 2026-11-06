import AppKit
import SwiftUI

/// A local drag commits only on drop. Merely hovering, Escape or dropping outside never edits settings.
@MainActor final class StatusCardDragController:ObservableObject {
    static let tokenSummary="token-summary"
    static let pasteboard=NSPasteboard.PasteboardType("local.showmac.status-card")
    @Published private(set) var sourceID:String?
    @Published var targetID:String?
    @Published var removalTarget=false
    private let nonce=UUID().uuidString
    private let model:AppModel
    var activeSource:StatusCardDragView?
    init(model:AppModel){self.model=model}
    var active:Bool {sourceID != nil}
    func begin(_ id:String,source:StatusCardDragView?=nil) {guard exists(id) else{return};sourceID=id;activeSource=source}
    func end(){sourceID=nil;targetID=nil;removalTarget=false;activeSource=nil}
    func token(_ id:String)->String {nonce+"|"+id}
    func resolve(_ token:String?)->String? {
        guard let token,let id=sourceID,token==self.token(id),exists(id) else{return nil};return id
    }
    func exists(_ id:String)->Bool {id==Self.tokenSummary ? model.showsStatusTokenSummary:model.statusPanel.cards.contains{$0.id==id}}
    func canRemove(_ id:String)->Bool {exists(id) && (id==Self.tokenSummary || model.statusPanel.cards.count>1)}
    @discardableResult func remove(_ token:String?)->Bool {
        guard let id=resolve(token),canRemove(id) else{return false}
        if id==Self.tokenSummary {model.statusPanel.showTokenSummary=false}
        else if let source=model.statusPanel.cards.first(where:{$0.id==id}) {model.removeStatusCard(source)}
        return true
    }
    @discardableResult func move(_ token:String?,before target:String)->Bool {
        guard let id=resolve(token),id != target,id != Self.tokenSummary,target != Self.tokenSummary else{return false}
        return model.moveStatusCard(id:id,before:target)
    }
}

/// Native mouse tracking provides click, press-and-hold and drag-session cancellation on macOS 11+.
struct StatusCardDragSurface:NSViewRepresentable {
    let controller:StatusCardDragController
    var id:String?
    var title:String=""
    var detail:String=""
    var trash=false
    var onOpen:()->Void={}
    func makeNSView(context:Context)->StatusCardDragView {let view=StatusCardDragView();updateNSView(view,context:context);return view}
    func updateNSView(_ view:StatusCardDragView,context:Context) {
        view.controller=controller;view.cardID=id;view.cardTitle=title;view.cardDetail=detail;view.trash=trash;view.onOpen=onOpen
        view.toolTip=trash ? L("拖到这里移除"):L("按住卡片拖动排序，拖到底部移除；点击查看详情。")
    }
}

@MainActor final class StatusCardDragView:NSView,NSDraggingSource {
    weak var controller:StatusCardDragController?
    var cardID:String?
    var cardTitle=""
    var cardDetail=""
    var trash=false
    var onOpen:()->Void={}
    private var down:NSEvent?
    private var hold:Timer?
    private var armed=false
    private var inSession=false
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {false}
    override init(frame:NSRect){super.init(frame:frame);registerForDraggedTypes([StatusCardDragController.pasteboard]);setAccessibilityElement(false)}
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override func viewWillMove(toWindow newWindow:NSWindow?) {
        if newWindow==nil {hold?.invalidate();hold=nil;if !inSession,controller?.sourceID==cardID {controller?.end()}}
        super.viewWillMove(toWindow:newWindow)
    }
    override func mouseDown(with event:NSEvent) {
        guard !trash,let id=cardID else{return}
        down=event;armed=false;hold?.invalidate()
        let timer=Timer(timeInterval:0.3,repeats:false){[weak self] _ in
            MainActor.assumeIsolated {guard let self,self.down != nil else{return};self.armed=true;self.controller?.begin(id,source:self)}
        }
        hold=timer;RunLoop.main.add(timer,forMode:.common)
    }
    override func mouseDragged(with event:NSEvent) {
        guard !trash,!inSession,let down,let id=cardID,let controller else{return}
        let a=convert(down.locationInWindow,from:nil),b=convert(event.locationInWindow,from:nil)
        guard hypot(a.x-b.x,a.y-b.y)>=5 else{return}
        hold?.invalidate();hold=nil;armed=true;inSession=true;controller.begin(id,source:self)
        let item=NSPasteboardItem();item.setString(controller.token(id),forType:StatusCardDragController.pasteboard)
        let drag=NSDraggingItem(pasteboardWriter:item)
        let preview=NSImage(size:bounds.size,flipped:true){[cardTitle=self.cardTitle,cardDetail=self.cardDetail] rect in
            NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill();NSBezierPath(roundedRect:rect,xRadius:12,yRadius:12).fill()
            (cardTitle as NSString).draw(in:NSRect(x:12,y:10,width:max(1,rect.width-24),height:20),withAttributes:[.font:NSFont.systemFont(ofSize:11,weight:.medium),.foregroundColor:NSColor.secondaryLabelColor])
            (cardDetail as NSString).draw(in:NSRect(x:12,y:31,width:max(1,rect.width-24),height:30),withAttributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:19,weight:.semibold),.foregroundColor:NSColor.labelColor])
            return true
        }
        drag.setDraggingFrame(bounds,contents:preview)
        let session=beginDraggingSession(with:[drag],event:event,source:self);session.animatesToStartingPositionsOnCancelOrFail=true
    }
    override func mouseUp(with event:NSEvent) {
        hold?.invalidate();hold=nil
        let click=down != nil && !armed && !inSession && bounds.contains(convert(event.locationInWindow,from:nil))
        down=nil
        if !inSession {if controller?.sourceID==cardID {controller?.end()};if click {onOpen()}}
    }
    func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext)->NSDragOperation {context == .withinApplication ? [.move,.delete]:[]}
    func ignoreModifierKeys(for session:NSDraggingSession)->Bool {true}
    func draggingSession(_ session:NSDraggingSession,endedAt screenPoint:NSPoint,operation:NSDragOperation) {
        inSession=false;down=nil;hold?.invalidate();hold=nil;controller?.end()
    }
    private func incoming(_ sender:NSDraggingInfo)->String? {controller?.resolve(sender.draggingPasteboard.string(forType:StatusCardDragController.pasteboard))}
    private func operation(_ sender:NSDraggingInfo)->NSDragOperation {
        guard let controller,let incoming=incoming(sender) else{return []}
        if trash {return controller.canRemove(incoming) ? .delete:[]}
        guard let target=cardID,incoming != target,incoming != StatusCardDragController.tokenSummary,target != StatusCardDragController.tokenSummary else{return []}
        return .move
    }
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation {
        let result=operation(sender)
        if !result.isEmpty {if trash {controller?.removalTarget=true}else{controller?.targetID=cardID}}
        return result
    }
    override func draggingUpdated(_ sender:NSDraggingInfo)->NSDragOperation {operation(sender)}
    override func draggingExited(_ sender:NSDraggingInfo?) {
        if trash {controller?.removalTarget=false}else if controller?.targetID==cardID {controller?.targetID=nil}
    }
    override func prepareForDragOperation(_ sender:NSDraggingInfo)->Bool {!operation(sender).isEmpty}
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool {
        guard !operation(sender).isEmpty,let controller else{return false}
        let token=sender.draggingPasteboard.string(forType:StatusCardDragController.pasteboard)
        return trash ? controller.remove(token):cardID.map{controller.move(token,before:$0)} ?? false
    }
}
