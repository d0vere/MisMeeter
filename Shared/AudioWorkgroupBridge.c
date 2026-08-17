#include <AudioToolbox/AudioToolbox.h>
#include <os/workgroup.h>
#include <stdlib.h>
#include <pthread.h>

typedef struct {
    os_workgroup_t workgroup;
    os_workgroup_join_token_s token;
    int joined;
} MisMeeterWGToken;

void *MisMeeterJoinAudioUnitWorkgroup(void *audioUnitPtr) {
    if (audioUnitPtr == NULL) {
        return NULL;
    }

    AudioUnit unit = (AudioUnit)audioUnitPtr;
    os_workgroup_t workgroup = NULL;
    UInt32 size = (UInt32)sizeof(workgroup);

    OSStatus status = AudioUnitGetProperty(
        unit,
        kAudioOutputUnitProperty_OSWorkgroup,
        kAudioUnitScope_Global,
        0,
        &workgroup,
        &size
    );

    // Some VoiceProcessingIO versions expose the workgroup on element 1.
    if ((status != noErr || workgroup == NULL)) {
        size = (UInt32)sizeof(workgroup);
        workgroup = NULL;

        status = AudioUnitGetProperty(
            unit,
            kAudioOutputUnitProperty_OSWorkgroup,
            kAudioUnitScope_Global,
            1,
            &workgroup,
            &size
        );
    }

    if (status != noErr || workgroup == NULL) {
        return NULL;
    }

    MisMeeterWGToken *holder =
        (MisMeeterWGToken *)calloc(1, sizeof(MisMeeterWGToken));

    if (holder == NULL) {
        return NULL;
    }

    // Keep the auxiliary TX thread at the highest ordinary QoS as well.
    // The Audio Workgroup relationship supplies the important audio deadline
    // information to the scheduler.
    (void)pthread_set_qos_class_self_np(
        QOS_CLASS_USER_INTERACTIVE,
        0
    );

    holder->workgroup = workgroup;

    int result = os_workgroup_join(
        holder->workgroup,
        &holder->token
    );

    if (result != 0) {
        free(holder);
        return NULL;
    }

    holder->joined = 1;
    return holder;
}

void MisMeeterLeaveAudioUnitWorkgroup(void *tokenPtr) {
    if (tokenPtr == NULL) {
        return;
    }

    MisMeeterWGToken *holder =
        (MisMeeterWGToken *)tokenPtr;

    if (holder->joined) {
        os_workgroup_leave(
            holder->workgroup,
            &holder->token
        );
        holder->joined = 0;
    }

    free(holder);
}
