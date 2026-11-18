import DistortionWavesKit

extension DistortionWaveStyle {
    /// The wave that rises from Send on the Us tab's drawing screen.
    static let widgetDrawingSend: DistortionWaveStyle = {
        var style = DistortionWaveStyle(type: .vertical)
        style.palette = .sunset
        // Nothing takes touches until the wave ends. The kit's colour and dots linger
        // for 3.6 s; these end it in about 2.3 s.
        style.rimFade = 1.8
        style.hairlineFade = 1.6
        style.particleLife = 1.8
        return style
    }()
}
