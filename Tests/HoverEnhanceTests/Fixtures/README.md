# Test fixtures

Short media files with neutral tags, for reading metadata. Made with ffmpeg:

```sh
ffmpeg -f lavfi -i "color=c=0x3a6ea5:s=48x48" -frames:v 1 cover.png
TAGS=(-metadata title="Example Song" -metadata artist="Example Artist" -metadata album="Example Album"
      -metadata album_artist="Example Album Artist" -metadata composer="Example Composer"
      -metadata genre="Ambient" -metadata date="2024" -metadata track="3/12" -metadata disc="1/2")
ffmpeg -f lavfi -t 1 -i "anullsrc=r=22050:cl=mono" -i cover.png -map 0:a -map 1:v -c:a libmp3lame -b:a 16k \
  -c:v copy -id3v2_version 3 "${TAGS[@]}" -disposition:v attached_pic tagged.mp3
ffmpeg -f lavfi -t 1 -i "anullsrc=r=22050:cl=mono" -i cover.png -map 0:a -map 1:v -c:a aac -b:a 16k \
  -c:v copy "${TAGS[@]}" -disposition:v attached_pic tagged.m4a
ffmpeg -f lavfi -t 1 -i "anullsrc=r=22050:cl=mono" -c:a libmp3lame -b:a 16k -map_metadata -1 \
  -id3v2_version 0 -write_id3v1 0 untagged.mp3
ffmpeg -f lavfi -i "testsrc=size=64x36:rate=24" -f lavfi -i "anullsrc=r=48000:cl=stereo" -t 1 \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 32k source.mov
```

`clip.mov` is `source.mov` re-exported with AVFoundation (`AVAssetExportSession`, passthrough) carrying
QuickTime metadata as cameras write it: `com.apple.quicktime.title` "Example Clip", `creationdate`
2024-05-06T07:08:09Z, `make` "ExampleCam", `model` "Model 1", and `software` "Example 2.0". ffmpeg's
own QuickTime tags don't come back under those identifiers.

## Weather

Real answers from the providers that need no key, for the parsers: Open-Meteo for its documented sample
point (Berlin, 52.52,13.41) on 2026-10-12, asked exactly as `OpenMeteo.forecastRequest` and `airRequest` ask,
and the National Weather Service's active alerts for Arizona that day (`/alerts/active?area=AZ`; a `point=`
answer has the same shape). Neither holds anything personal.

The keyed providers' samples come from their documentation, as no key was used to make them:
`owm-*.json` are OpenWeatherMap's examples (converted from Kelvin to °C, as `units=metric` answers),
`tomorrow-*.json` are Tomorrow.io's examples verbatim, and `weatherapi-forecast.json` and
`pirateweather-forecast.json` are built on WeatherAPI.com's and Pirate Weather's own examples, filled out
with made-up values to their published schemas. `accuweather-*.json` follow AccuWeather's published
schemas (for New York, location key 349727, its documentation's example) with made-up values, asked as
`AccuWeather` asks: details on, forecasts in metric.
