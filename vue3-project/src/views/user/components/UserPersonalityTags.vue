<template>
    <div class="personality-tags" v-if="hasVisibleTags">
        <span v-for="(tag, index) in visibleTags" :key="index" class="tag">
            <SvgIcon v-if="index === 0 && showGenderIcon" :name="genderIcon" width="14" height="14"
                class="gender-icon" />
            {{ tag }}
        </span>
    </div>
</template>

<script setup>
import { computed } from 'vue'
import SvgIcon from '@/components/SvgIcon.vue'

const props = defineProps({
    userInfo: {
        type: Object,
        default: () => ({})
    }
})

const genderIcons = {
    '男': 'male',
    '女': 'female'
}

const visibleTags = computed(() => {
    const tags = []
    const userInfo = props.userInfo

    if (!userInfo) return tags

    const tagFields = [
        { key: 'zodiac_sign', label: userInfo.zodiac_sign },
        { key: 'mbti', label: userInfo.mbti },
        { key: 'education', label: userInfo.education },
        { key: 'major', label: userInfo.major }
    ]

    tagFields.forEach(field => {
        if (field.label && field.label.trim()) {
            tags.push(field.label)
        }
    })

    const interests = userInfo.interests || ''
    let interestArray = []

    if (typeof interests === 'string') {
        if (interests.trim()) {
            try {
                const parsed = JSON.parse(interests)
                interestArray = Array.isArray(parsed) ? parsed : []
            } catch {
                interestArray = interests.split(',').map(item => item.trim()).filter(item => item)
            }
        } else {
            interestArray = []
        }
    } else if (Array.isArray(interests)) {
        interestArray = interests
    }

    interestArray.forEach(interest => {
        if (interest && interest.trim()) {
            tags.push(interest)
        }
    })

    return tags
})

const genderIcon = computed(() => {
    const userInfo = props.userInfo
    return userInfo.gender && genderIcons[userInfo.gender] ? genderIcons[userInfo.gender] : null
})

const showGenderIcon = computed(() => {
    return visibleTags.value.length > 0 && genderIcon.value
})

const hasVisibleTags = computed(() => {
    return visibleTags.value.length > 0
})
</script>

<style scoped>
.personality-tags {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px;
    margin-top: 8px;
    padding: 0 16px;
}

@media (min-width: 901px) {
    .personality-tags {
        padding: 0;
    }
}

.tag {
    display: inline-flex;
    align-items: center;
    padding: 4px 8px;
    background-color: var(--bg-color-secondary);
    color: var(--text-color-secondary);
    border-radius: 12px;
    font-size: 12px;
    line-height: 1.2;
    white-space: nowrap;
    border: 1px solid var(--border-color-primary);
    transition: all 0.2s ease;
}

.tag .gender-icon {
    margin-right: 4px;
    color: var(--text-color-secondary);
}

@media (max-width: 480px) {
    .personality-tags {
        gap: 6px;
        padding: 0 16px;
    }

    .tag {
        padding: 3px 6px;
        font-size: 11px;
    }
}
</style>