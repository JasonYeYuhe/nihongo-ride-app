import CoreGraphics
import CoreText
import ImageIO
import Foundation
import UniformTypeIdentifiers

let S = 1024
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
func rgb(_ r: Double,_ g: Double,_ b: Double) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: 1) }
let coral=rgb(0.98,0.45,0.45), sky=rgb(0.42,0.78,0.98), gold=rgb(0.98,0.80,0.35), indigo=rgb(0.20,0.30,0.62)

struct Badge { let name:String; let c1:CGColor; let c2:CGColor; let glyph:String; let emoji:Bool }
let badges:[Badge] = [
    Badge(name:"leaderboard_ta_score", c1:gold,  c2:rgb(0.86,0.55,0.18), glyph:"🏆", emoji:true),
    Badge(name:"first_ride",           c1:coral, c2:rgb(0.80,0.28,0.40), glyph:"🏁", emoji:true),
    Badge(name:"words_100",            c1:sky,   c2:indigo,              glyph:"100", emoji:false),
    Badge(name:"words_1000",           c1:rgb(0.55,0.70,0.98), c2:rgb(0.18,0.24,0.55), glyph:"1000", emoji:false),
    Badge(name:"streak_7",             c1:coral, c2:gold,                glyph:"🔥", emoji:true),
    Badge(name:"flawless",             c1:gold,  c2:rgb(0.92,0.62,0.30), glyph:"⭐️", emoji:true),
]
let fontKey  = NSAttributedString.Key(kCTFontAttributeName as String)
let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)

func render(_ b: Badge) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data:nil,width:S,height:S,bitsPerComponent:8,bytesPerRow:0,
                        space:cs,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
    let grad = CGGradient(colorsSpace:cs, colors:[b.c1,b.c2] as CFArray, locations:[0,1])!
    ctx.drawLinearGradient(grad, start:CGPoint(x:0,y:S), end:CGPoint(x:S,y:0), options:[])
    ctx.setStrokeColor(CGColor(red:1,green:1,blue:1,alpha:0.18)); ctx.setLineWidth(14)
    ctx.addEllipse(in:CGRect(x:120,y:120,width:S-240,height:S-240)); ctx.strokePath()

    let fontSize:CGFloat = b.emoji ? 520 : (b.glyph.count >= 4 ? 360 : 460)
    let fontName = b.emoji ? "AppleColorEmoji" : "Avenir-Black"
    let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
    var attrs:[NSAttributedString.Key:Any] = [fontKey: font]
    if !b.emoji { attrs[colorKey] = CGColor(red:1,green:1,blue:1,alpha:1) }
    let line = CTLineCreateWithAttributedString(NSAttributedString(string:b.glyph, attributes:attrs))
    var asc:CGFloat=0, desc:CGFloat=0, lead:CGFloat=0
    let w = CGFloat(CTLineGetTypographicBounds(line,&asc,&desc,&lead))
    ctx.textPosition = CGPoint(x:(CGFloat(S)-w)/2, y:CGFloat(S)/2 - (asc-desc)/2)
    CTLineDraw(line, ctx)

    let img = ctx.makeImage()!
    let url = URL(fileURLWithPath:"\(outDir)/\(b.name).png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
    print("wrote \(b.name).png")
}
for b in badges { render(b) }
