/**
 * 商城页面通用轻量消息提示（toast）
 * 在页面顶部居中短暂显示，自动消失。
 * @param {string} message
 * @param {'success'|'error'|'warning'|'info'} type
 * @param {number} duration 毫秒
 */
export function showShopMessage(message, type = 'success', duration = 2500) {
    if (typeof document === 'undefined') return
    const el = document.createElement('div')
    el.className = `shop-toast ${type}`
    el.textContent = message
    Object.assign(el.style, {
        position: 'fixed',
        top: '20px',
        left: '50%',
        transform: 'translateX(-50%)',
        padding: '10px 22px',
        borderRadius: '8px',
        color: '#fff',
        fontSize: '14px',
        zIndex: '10000',
        opacity: '0',
        transition: 'opacity 0.25s ease',
        boxShadow: '0 4px 12px rgba(0,0,0,0.15)',
        maxWidth: '80vw',
        wordBreak: 'break-word'
    })
    const colors = {
        success: '#67C23A',
        error: '#F56C6C',
        warning: '#E6A23C',
        info: '#409EFF'
    }
    el.style.backgroundColor = colors[type] || colors.info
    document.body.appendChild(el)
    requestAnimationFrame(() => { el.style.opacity = '1' })
    setTimeout(() => {
        el.style.opacity = '0'
        setTimeout(() => {
            if (el.parentNode) document.body.removeChild(el)
        }, 250)
    }, duration)
}

export default showShopMessage
