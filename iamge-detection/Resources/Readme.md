# MobileCLIP model assets

The `clip-model/` folder is **gitignored** because it contains large binary files (~480 MB total). After cloning the repo, download the assets and place them here:

```
iamge-detection/Resources/clip-model/
├── mobileclip2_s3_image.mlpackage
├── mobileclip2_s3_text.mlpackage
├── clip-vocab.json
└── clip-merges.txt
```

## Download

Download all files from Google Drive:

**https://drive.google.com/drive/folders/1f10r7IFW5x5P7u7xb86qctz0f66dJO8u?usp=drive_link**

Copy the contents into `iamge-detection/Resources/clip-model/`. The app will not run without these files — `MobileCLIPClassifier` loads the Core ML models and `CLIPTokenizer` reads the vocab/merges files at launch.

First build may take 1–2 minutes while Core ML compiles the models.
