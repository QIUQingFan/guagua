<template>
  <CrudTable title="管理员管理" entity-name="管理员" api-endpoint="/admin/admins" :columns="columns" :form-fields="formFields"
    :search-fields="searchFields" />
</template>

<script setup>
import CrudTable from '@/views/admin/components/CrudTable.vue'

const roleOptions = [
  { value: 'super_admin', label: '超级管理员' },
  { value: 'developer', label: '开发人员' },
  { value: 'merchant', label: '商家' }
]


const roleLabelMap = {
  super_admin: '超级管理员',
  developer: '开发人员',
  merchant: '商家'
}

const columns = [
  { key: 'username', label: '账号', sortable: false },
  { key: 'role', label: '角色', sortable: false, type: 'mapped', map: roleLabelMap },
  { key: 'password', label: '密码', sortable: false },
  { key: 'created_at', label: '创建时间', type: 'date', sortable: true }
]

const formFields = [
  { key: 'username', label: '账号', type: 'text', required: true, placeholder: '请输入账号' },
  { key: 'password', label: '密码', type: 'password', required: true, placeholder: '请输入密码' },
  { key: 'role', label: '角色', type: 'select', options: roleOptions, default: 'developer' }
]

const searchFields = [
  { key: 'username', label: '账号', placeholder: '搜索账号' }
]
</script>
