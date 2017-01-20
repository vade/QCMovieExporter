# QCMovieExporter
AVFoundation  / QC Exporter / Replacement for QuartzCrystal

Provided as is - I dont want to hear any fucking complaints. 

Known Issues:

* Patches that scrape the 'front buffer' such as the Syphon Server patch when in 'OpenGL' mode will cause a GL error and may cause issues for downstream patches. (There is no front buffer for our render path - which is the cause of the issue).

* Auto-Restored documents do not function ye. Close and open them manually to have them work 

* Occasional weirdness.
