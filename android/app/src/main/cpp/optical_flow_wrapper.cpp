// android/app/src/main/cpp/optical_flow_wrapper.cpp
// MODULE 1 – OpenCV Optical Flow Native Wrapper
//
// Implements sparse Lucas-Kanade optical flow for ego-motion estimation.
// Called from MainActivity.kt via JNI:
//   Java_com_sightmate_blindassist_MainActivity_computeOpticalFlowNative
//
// Algorithm:
//   1. Detect Shi-Tomasi corners in previous Y-plane frame
//   2. Track corners to current frame using calcOpticalFlowPyrLK
//   3. Filter out bad tracks (status=0, large error)
//   4. Estimate affine transform (estimateAffinePartial2D)
//   5. Decompose affine matrix into [dx, dy, rotation, scale]
//   6. Return as JNI map to Kotlin/Dart
//
// Build: Android NDK via CMakeLists.txt in android/app/src/main/cpp/
// OpenCV: OpenCV4Android SDK must be placed in android/opencv/

#include <jni.h>
#include <string>
#include <vector>
#include <android/log.h>

#define LOG_TAG "SightMateCV"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#ifdef HAVE_OPENCV
#include <opencv2/core.hpp>
#include <opencv2/video/tracking.hpp>
#include <opencv2/imgproc.hpp>

// ── Constants ─────────────────────────────────────────────────────────────────

static const int   MAX_CORNERS        = 200;  // Shi-Tomasi corner count
static const float QUALITY_LEVEL      = 0.01f;
static const float MIN_DISTANCE       = 10.0f;
static const int   LK_WIN_SIZE        = 21;
static const int   LK_MAX_ITER        = 20;
static const float LK_EPSILON         = 0.03f;
static const float MIN_GOOD_POINTS    = 10;    // Minimum tracked points for reliable result
static const float RANSAC_REPROJ_THRESH = 3.0f;

// ── Core computation ──────────────────────────────────────────────────────────

struct EgoMotion {
    double dx       = 0.0;
    double dy       = 0.0;
    double rotation = 0.0;
    double scale    = 1.0;
    double vp_x     = 0.5;  // Default normalized vanishing point
    double vp_y     = 0.42;
    bool   reliable = false;
};

EgoMotion computeEgoMotion(
    const cv::Mat& prev,
    const cv::Mat& curr,
    int width,
    int height
) {
    EgoMotion result;

    if (prev.empty() || curr.empty()) return result;

    // 1. Detect good features in previous frame
    std::vector<cv::Point2f> prevPoints;
    cv::goodFeaturesToTrack(
        prev, prevPoints,
        MAX_CORNERS,
        QUALITY_LEVEL,
        MIN_DISTANCE,
        cv::noArray(),
        3,           // blockSize
        false,       // useHarrisDetector
        0.04
    );

    if (prevPoints.size() < MIN_GOOD_POINTS) {
        LOGW("Insufficient corners: %zu", prevPoints.size());
        return result;
    }

    // 2. Lucas-Kanade tracking
    std::vector<cv::Point2f> currPoints;
    std::vector<uchar> status;
    std::vector<float> err;

    cv::TermCriteria criteria(
        cv::TermCriteria::COUNT + cv::TermCriteria::EPS,
        LK_MAX_ITER,
        LK_EPSILON
    );

    cv::calcOpticalFlowPyrLK(
        prev, curr,
        prevPoints, currPoints,
        status, err,
        cv::Size(LK_WIN_SIZE, LK_WIN_SIZE),
        3,          // maxLevel (pyramid levels)
        criteria
    );

    // 3. Filter out bad tracks
    std::vector<cv::Point2f> goodPrev, goodCurr;
    for (size_t i = 0; i < status.size(); i++) {
        if (status[i] && err[i] < 50.0f) {
            goodPrev.push_back(prevPoints[i]);
            goodCurr.push_back(currPoints[i]);
        }
    }

    if ((int)goodPrev.size() < MIN_GOOD_POINTS) {
        LOGW("Too few good tracks: %zu", goodPrev.size());
        return result;
    }

    // 4. Estimate affine transform (partial: translation + rotation + uniform scale)
    cv::Mat inlierMask;
    cv::Mat affine = cv::estimateAffinePartial2D(
        goodPrev, goodCurr,
        inlierMask,
        cv::RANSAC,
        RANSAC_REPROJ_THRESH
    );

    if (affine.empty()) {
        LOGW("Affine estimation failed.");
        return result;
    }

    // 5. Decompose affine [a, b, tx; -b, a, ty]
    double a  = affine.at<double>(0, 0);
    double b  = affine.at<double>(0, 1);
    double tx = affine.at<double>(0, 2);
    double ty = affine.at<double>(1, 2);

    result.dx       = tx;
    result.dy       = ty;
    result.rotation = std::atan2(b, a);
    double det_R    = a * a + b * b;
    result.scale    = std::sqrt(det_R);
    result.reliable = true;

    // 6. Dynamic Vanishing Point estimation using least-squares intersection of compensated flow vectors
    if (det_R > 1e-6) {
        double inv_a  = a / det_R;
        double inv_b  = -b / det_R;
        double inv_tx = -(inv_a * tx + inv_b * ty);
        double inv_ty = -(-inv_b * tx + inv_a * ty);

        double A_00 = 0.0, A_01 = 0.0, A_11 = 0.0;
        double b_0  = 0.0, b_1  = 0.0;
        int count = 0;

        for (size_t i = 0; i < goodPrev.size(); i++) {
            // Warp current point back to previous frame's coordinate space (camera motion compensation)
            double cx = inv_a * goodCurr[i].x + inv_b * goodCurr[i].y + inv_tx;
            double cy = -inv_b * goodCurr[i].x + inv_a * goodCurr[i].y + inv_ty;

            // Pure expansion vector (after camera motion subtraction)
            double vx = goodPrev[i].x - cx;
            double vy = goodPrev[i].y - cy;
            double mag = std::sqrt(vx * vx + vy * vy);

            // Only use vectors with significant movement to avoid static noise
            if (mag > 0.5) {
                double dx = vx / mag;
                double dy = vy / mag;

                // Accumulate least-squares intersection parameters
                A_00 += (1.0 - dx * dx);
                A_01 += -dx * dy;
                A_11 += (1.0 - dy * dy);

                b_0 += (1.0 - dx * dx) * goodPrev[i].x - dx * dy * goodPrev[i].y;
                b_1 += -dx * dy * goodPrev[i].x + (1.0 - dy * dy) * goodPrev[i].y;
                count++;
            }
        }

        if (count >= 8) {
            double det = A_00 * A_11 - A_01 * A_01;
            if (std::abs(det) > 1e-4) {
                double vp_x = (A_11 * b_0 - A_01 * b_1) / det;
                double vp_y = (A_00 * b_1 - A_01 * b_0) / det;

                // Validate that the vanishing point is inside a reasonable frame expansion boundary
                if (vp_x >= -width * 0.5 && vp_x <= width * 1.5 &&
                    vp_y >= -height * 0.5 && vp_y <= height * 1.5) {
                    result.vp_x = vp_x / width;
                    result.vp_y = vp_y / height;
                }
            }
        }
    }

    LOGI("EgoMotion: dx=%.2f dy=%.2f rot=%.4f scale=%.4f vp=(%.3f, %.3f)",
         result.dx, result.dy, result.rotation, result.scale, result.vp_x, result.vp_y);

    return result;
}

#endif // HAVE_OPENCV

// ── JNI Entry Point ───────────────────────────────────────────────────────────

extern "C" JNIEXPORT jobject JNICALL
Java_com_sightmate_blindassist_MainActivity_computeOpticalFlowNative(
    JNIEnv* env,
    jobject /* this */,
    jbyteArray prevYArray,
    jbyteArray currYArray,
    jint width,
    jint height
) {
    // Helper to build a Java HashMap
    auto makeHashMap = [&]() -> jobject {
        jclass mapClass = env->FindClass("java/util/HashMap");
        jmethodID init  = env->GetMethodID(mapClass, "<init>", "()V");
        return env->NewObject(mapClass, init);
    };

    auto mapPut = [&](jobject map, const char* key, double value) {
        jclass    mapClass  = env->FindClass("java/util/HashMap");
        jmethodID put       = env->GetMethodID(mapClass, "put",
            "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
        jclass    dblClass  = env->FindClass("java/lang/Double");
        jmethodID dblInit   = env->GetStaticMethodID(dblClass, "valueOf", "(D)Ljava/lang/Double;");
        jobject   jValue    = env->CallStaticObjectMethod(dblClass, dblInit, value);
        jobject   jKey      = env->NewStringUTF(key);
        env->CallObjectMethod(map, put, jKey, jValue);
        env->DeleteLocalRef(jKey);
        env->DeleteLocalRef(jValue);
    };

    auto mapPutBool = [&](jobject map, const char* key, bool value) {
        jclass    mapClass  = env->FindClass("java/util/HashMap");
        jmethodID put       = env->GetMethodID(mapClass, "put",
            "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
        jclass    boolClass = env->FindClass("java/lang/Boolean");
        jmethodID boolInit  = env->GetStaticMethodID(boolClass, "valueOf", "(Z)Ljava/lang/Boolean;");
        jobject   jValue    = env->CallStaticObjectMethod(boolClass, boolInit, (jboolean)value);
        jobject   jKey      = env->NewStringUTF(key);
        env->CallObjectMethod(map, put, jKey, jValue);
        env->DeleteLocalRef(jKey);
        env->DeleteLocalRef(jValue);
    };

    jobject resultMap = makeHashMap();

#ifdef HAVE_OPENCV
    // Get byte arrays from JNI
    jbyte* prevBytes = env->GetByteArrayElements(prevYArray, nullptr);
    jbyte* currBytes = env->GetByteArrayElements(currYArray, nullptr);

    if (!prevBytes || !currBytes) {
        mapPut(resultMap, "dx",       0.0);
        mapPut(resultMap, "dy",       0.0);
        mapPut(resultMap, "rotation", 0.0);
        mapPut(resultMap, "scale",    1.0);
        mapPut(resultMap, "vp_x",     0.5);
        mapPut(resultMap, "vp_y",     0.42);
        mapPutBool(resultMap, "reliable", false);
        if (prevBytes) env->ReleaseByteArrayElements(prevYArray, prevBytes, JNI_ABORT);
        if (currBytes) env->ReleaseByteArrayElements(currYArray, currBytes, JNI_ABORT);
        return resultMap;
    }

    // Wrap in OpenCV Mat (Y plane = 8-bit grayscale)
    cv::Mat prevMat(height, width, CV_8UC1, reinterpret_cast<uint8_t*>(prevBytes));
    cv::Mat currMat(height, width, CV_8UC1, reinterpret_cast<uint8_t*>(currBytes));

    EgoMotion motion = computeEgoMotion(prevMat, currMat, width, height);

    env->ReleaseByteArrayElements(prevYArray, prevBytes, JNI_ABORT);
    env->ReleaseByteArrayElements(currYArray, currBytes, JNI_ABORT);

    mapPut(resultMap,     "dx",       motion.dx);
    mapPut(resultMap,     "dy",       motion.dy);
    mapPut(resultMap,     "rotation", motion.rotation);
    mapPut(resultMap,     "scale",    motion.scale);
    mapPut(resultMap,     "vp_x",     motion.vp_x);
    mapPut(resultMap,     "vp_y",     motion.vp_y);
    mapPutBool(resultMap, "reliable", motion.reliable);

#else
    // OpenCV not compiled in — return zero motion and default vanishing point
    mapPut(resultMap,     "dx",       0.0);
    mapPut(resultMap,     "dy",       0.0);
    mapPut(resultMap,     "rotation", 0.0);
    mapPut(resultMap,     "scale",    1.0);
    mapPut(resultMap,     "vp_x",     0.5);
    mapPut(resultMap,     "vp_y",     0.42);
    mapPutBool(resultMap, "reliable", false);
#endif

    return resultMap;
}
