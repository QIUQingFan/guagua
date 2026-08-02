<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useUserStore } from '@/stores/user.js'
import { getAddresses, createAddress, updateAddress, deleteAddress } from '@/api/shop.js'
import SvgIcon from '@/components/SvgIcon.vue'
import { showShopMessage } from '@/utils/shopMessage.js'

const router = useRouter()
const userStore = useUserStore()

const list = ref([])
const isLoading = ref(false)
const submitting = ref(false)

const showModal = ref(false)
const isEdit = ref(false)
const form = ref(emptyForm())

function emptyForm() {
    return {
        id: null,
        receiver: '',
        phone: '',
        province: '',
        city: '',
        district: '',
        detail: '',
        is_default: 0
    }
}

const PHONE_RE = /^1[3-9]\d{9}$/

function validateForm() {
    const f = form.value
    const required = [
        { key: 'receiver', label: '收货人' },
        { key: 'phone', label: '手机号' },
        { key: 'province', label: '省份' },
        { key: 'city', label: '城市' },
        { key: 'district', label: '区/县' },
        { key: 'detail', label: '详细地址' }
    ]
    for (const item of required) {
        if (!String(f[item.key] || '').trim()) {
            return `${item.label}不能为空`
        }
    }
    if (!PHONE_RE.test(String(f.phone).trim())) {
        return '手机号格式不正确'
    }
    if (String(f.detail).trim().length > 200) {
        return '详细地址过长（最多200字）'
    }
    return ''
}

async function fetchList() {
    if (!userStore.isLoggedIn) return
    isLoading.value = true
    try {
        const res = await getAddresses()
        if (res.success) list.value = res.data || []
    } finally {
        isLoading.value = false
    }
}

function openAdd() {
    isEdit.value = false
    form.value = emptyForm()
    showModal.value = true
}

function openEdit(addr) {
    isEdit.value = true
    form.value = {
        id: addr.id,
        receiver: addr.receiver,
        phone: addr.phone,
        province: addr.province,
        city: addr.city,
        district: addr.district,
        detail: addr.detail,
        is_default: Number(addr.is_default) === 1 ? 1 : 0
    }
    showModal.value = true
}

function closeModal() {
    if (submitting.value) return
    showModal.value = false
}

async function submitForm() {
    const msg = validateForm()
    if (msg) {
        showShopMessage(msg, 'warning')
        return
    }
    const f = form.value
    const payload = {
        receiver: String(f.receiver).trim(),
        phone: String(f.phone).trim(),
        province: String(f.province).trim(),
        city: String(f.city).trim(),
        district: String(f.district).trim(),
        detail: String(f.detail).trim(),
        is_default: f.is_default ? 1 : 0
    }
    submitting.value = true
    try {
        let res
        if (isEdit.value) {
            res = await updateAddress(f.id, payload)
        } else {
            res = await createAddress(payload)
        }
        if (res.success) {
            showShopMessage(isEdit.value ? '修改成功' : '添加成功', 'success')
            showModal.value = false
            await fetchList()
        } else {
            showShopMessage(res.message || '操作失败', 'error')
        }
    } finally {
        submitting.value = false
    }
}

async function handleSetDefault(addr) {
    if (Number(addr.is_default) === 1) return
    submitting.value = true
    try {
        const res = await updateAddress(addr.id, { is_default: 1 })
        if (res.success) {
            showShopMessage('已设为默认', 'success')
            await fetchList()
        } else {
            showShopMessage(res.message || '操作失败', 'error')
        }
    } finally {
        submitting.value = false
    }
}

async function handleDelete(addr) {
    if (!confirm(`确定删除该收货地址？`)) return
    const res = await deleteAddress(addr.id)
    if (res.success) {
        showShopMessage('删除成功', 'success')
        await fetchList()
    } else {
        showShopMessage(res.message || '删除失败', 'error')
    }
}

function goBack() {
    if (window.history.length > 1) {
        router.back()
    } else {
        router.push({ name: 'shop_home' })
    }
}

onMounted(() => {
    if (!userStore.isLoggedIn) {
        showShopMessage('请先登录', 'warning')
        router.push({ name: 'shop_home' })
        return
    }
    fetchList()
})
</script>

<template>
    <div class="address-page">
        <div class="back-bar">
            <button class="back-btn" @click="goBack">
                <SvgIcon name="left" width="18" height="18" /> 返回
            </button>
            <h1 class="page-title">收货地址</h1>
            <button class="add-btn" @click="openAdd">+ 新增</button>
        </div>

        <div v-if="isLoading && list.length === 0" class="state-text">加载中...</div>

        <div v-else-if="list.length === 0" class="empty-state">
            <p class="empty-text">还没有收货地址</p>
            <button class="primary-btn" @click="openAdd">添加地址</button>
        </div>

        <div v-else class="address-list">
            <div v-for="addr in list" :key="addr.id" class="address-card">
                <div class="card-main">
                    <div class="card-top">
                        <span class="receiver">{{ addr.receiver }}</span>
                        <span class="phone">{{ addr.phone }}</span>
                        <span v-if="Number(addr.is_default) === 1" class="default-tag">默认</span>
                    </div>
                    <div class="card-detail">
                        {{ addr.province }}{{ addr.city }}{{ addr.district }}{{ addr.detail }}
                    </div>
                </div>
                <div class="card-actions">
                    <button
                        v-if="Number(addr.is_default) !== 1"
                        class="op-btn"
                        :disabled="submitting"
                        @click="handleSetDefault(addr)"
                    >
                        设为默认
                    </button>
                    <button class="op-btn" @click="openEdit(addr)">编辑</button>
                    <button class="op-btn danger" @click="handleDelete(addr)">删除</button>
                </div>
            </div>
        </div>

        <div v-if="showModal" class="modal-mask" @click.self="closeModal">
            <div class="modal">
                <div class="modal-header">
                    <h2 class="modal-title">{{ isEdit ? '编辑地址' : '新增地址' }}</h2>
                    <button class="modal-close" @click="closeModal">×</button>
                </div>
                <div class="modal-body">
                    <div class="form-row">
                        <label class="form-label">收货人</label>
                        <input v-model="form.receiver" class="form-input" placeholder="请输入收货人姓名" maxlength="32" />
                    </div>
                    <div class="form-row">
                        <label class="form-label">手机号</label>
                        <input v-model="form.phone" class="form-input" placeholder="请输入11位手机号" maxlength="11" />
                    </div>
                    <div class="form-row form-row-3">
                        <div class="form-col">
                            <label class="form-label">省</label>
                            <input v-model="form.province" class="form-input" placeholder="省" maxlength="32" />
                        </div>
                        <div class="form-col">
                            <label class="form-label">市</label>
                            <input v-model="form.city" class="form-input" placeholder="市" maxlength="32" />
                        </div>
                        <div class="form-col">
                            <label class="form-label">区/县</label>
                            <input v-model="form.district" class="form-input" placeholder="区/县" maxlength="32" />
                        </div>
                    </div>
                    <div class="form-row">
                        <label class="form-label">详细地址</label>
                        <textarea
                            v-model="form.detail"
                            class="form-input form-textarea"
                            placeholder="街道、楼牌号等"
                            maxlength="200"
                            rows="2"
                        ></textarea>
                    </div>
                    <label class="default-check">
                        <input type="checkbox" :checked="form.is_default === 1" @change="form.is_default = $event.target.checked ? 1 : 0" />
                        <span>设为默认地址</span>
                    </label>
                </div>
                <div class="modal-footer">
                    <button class="modal-btn cancel" :disabled="submitting" @click="closeModal">取消</button>
                    <button class="modal-btn confirm" :disabled="submitting" @click="submitForm">
                        {{ submitting ? '提交中...' : '保存' }}
                    </button>
                </div>
            </div>
        </div>
    </div>
</template>

<style scoped>
.address-page {
    padding: 72px 24px 24px;
    width: 100%;
    box-sizing: border-box;
}

.back-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 16px;
}

.back-btn {
    display: flex;
    align-items: center;
    gap: 4px;
    background: transparent;
    color: var(--text-color-secondary);
    border: none;
    cursor: pointer;
    font-size: 14px;
    padding: 6px 0;
}

.page-title {
    font-size: 20px;
    font-weight: 700;
    margin: 0;
    color: var(--text-color-primary);
}

.add-btn {
    background: var(--primary-color);
    color: #fff;
    border: none;
    border-radius: 999px;
    padding: 6px 18px;
    font-size: 14px;
    cursor: pointer;
}

.state-text {
    text-align: center;
    color: var(--text-color-tertiary, #999);
    padding: 60px 0;
}

.empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    padding: 80px 0;
}

.empty-text {
    color: var(--text-color-tertiary, #999);
    font-size: 15px;
    margin: 0;
}

.primary-btn {
    background: var(--primary-color);
    color: #fff;
    border: none;
    border-radius: 999px;
    padding: 10px 32px;
    font-size: 14px;
    cursor: pointer;
}

.address-list {
    display: flex;
    flex-direction: column;
    gap: 12px;
}

.address-card {
    background: var(--bg-color-secondary);
    border-radius: 12px;
    padding: 16px;
}

.card-main {
    margin-bottom: 12px;
}

.card-top {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-bottom: 6px;
}

.receiver {
    font-size: 16px;
    font-weight: 600;
    color: var(--text-color-primary);
}

.phone {
    font-size: 14px;
    color: var(--text-color-secondary);
}

.default-tag {
    font-size: 11px;
    color: var(--primary-color);
    border: 1px solid var(--primary-color);
    border-radius: 4px;
    padding: 0 6px;
}

.card-detail {
    font-size: 14px;
    color: var(--text-color-secondary);
    line-height: 1.5;
}

.card-actions {
    display: flex;
    gap: 8px;
    justify-content: flex-end;
    padding-top: 10px;
    border-top: 1px solid var(--border-color-primary, #eee);
}

.op-btn {
    background: none;
    border: 1px solid var(--border-color-primary, #ddd);
    border-radius: 999px;
    padding: 4px 14px;
    font-size: 13px;
    color: var(--text-color-secondary);
    cursor: pointer;
}

.op-btn:hover {
    color: var(--primary-color);
    border-color: var(--primary-color);
}

.op-btn.danger:hover {
    color: #f56c6c;
    border-color: #f56c6c;
}

.op-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
}

.modal-mask {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
    padding: 16px;
}

.modal {
    background: var(--bg-color-primary);
    border-radius: 12px;
    width: 100%;
    max-width: 460px;
    max-height: 90vh;
    overflow-y: auto;
}

.modal-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 16px 20px;
    border-bottom: 1px solid var(--border-color-primary, #eee);
}

.modal-title {
    font-size: 17px;
    font-weight: 700;
    margin: 0;
    color: var(--text-color-primary);
}

.modal-close {
    background: none;
    border: none;
    font-size: 26px;
    color: var(--text-color-tertiary, #999);
    cursor: pointer;
    line-height: 1;
    padding: 0;
}

.modal-body {
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 14px;
}

.form-row {
    display: flex;
    flex-direction: column;
    gap: 6px;
}

.form-row-3 {
    flex-direction: row;
    gap: 10px;
}

.form-col {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 6px;
}

.form-label {
    font-size: 13px;
    color: var(--text-color-secondary);
}

.form-input {
    border: 1px solid var(--border-color-primary, #eee);
    border-radius: 8px;
    padding: 10px 12px;
    font-size: 14px;
    color: var(--text-color-primary);
    background: var(--bg-color-primary);
    outline: none;
    box-sizing: border-box;
    font-family: inherit;
    width: 100%;
}

.form-input:focus {
    border-color: var(--primary-color);
}

.form-textarea {
    resize: none;
}

.default-check {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 14px;
    color: var(--text-color-primary);
    cursor: pointer;
}

.default-check input {
    accent-color: var(--primary-color);
    width: 16px;
    height: 16px;
}

.modal-footer {
    display: flex;
    gap: 12px;
    padding: 16px 20px;
    border-top: 1px solid var(--border-color-primary, #eee);
    justify-content: flex-end;
}

.modal-btn {
    border-radius: 999px;
    padding: 8px 28px;
    font-size: 14px;
    cursor: pointer;
    border: none;
}

.modal-btn.cancel {
    background: var(--bg-color-secondary);
    color: var(--text-color-secondary);
}

.modal-btn.confirm {
    background: var(--primary-color);
    color: #fff;
}

.modal-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
}

@media (max-width: 480px) {
    .form-row-3 {
        flex-direction: column;
    }
}
</style>
